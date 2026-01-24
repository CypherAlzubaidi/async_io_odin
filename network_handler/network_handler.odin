package network_handler
import error_c "../Error_code"
import cb "../circular_buffer"
import io_u "../io_utils"
import mp "../memory_pool"
import "core:crypto/poly1305"
import "core:flags"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:slice"
import "core:sys/linux"
import "core:sys/posix"
import "core:sys/unix"
@(private)
State :: enum {
	Nothing,
	Active,
	Deinit,
	Error,
}

Handler_Action :: enum {
	None,
	Deinit,
	Server_Shutdown,
}

Epoll_Event_Type :: enum {
	In,
	Out,
	Error,
}

@(private)
Handler_Type :: enum {
	Recv,
	Send,
	Acceptor,
}


@(private)
Data_Handler :: struct {
	callback_func:      Callback_Handler,
	stop_callback_func: Callback_Stop,
	data:               rawptr,
	fd:                 linux.Fd,
	flag:               bool,
	type:               Handler_Type,
	state:              State,
}

Network_Pool :: struct {
	container: [dynamic]^Network_Tcp_Handler,
}

Network_Tcp_Handler :: struct {
	conn:               net.TCP_Socket,
	operation_complete: bool,
	buffer:             [1024]u8,
	bytes_transferred:  int,
	last_error:         error_c.Error_Code,
	user_data:          rawptr,
}

Acceptor_Handler :: struct {
	server_socket: net.TCP_Socket,
	event_loop:    rawptr,
	callback:      Acceptor_Callback,
	user_data:     rawptr,
	last_error:    error_c.Error_Code,
}

/////////////////////////// Network Pool Operations ///////////////////////////

Init_Network_Handler_Pool :: proc(pool: ^Network_Pool) {
	pool.container = make([dynamic]^Network_Tcp_Handler)
}

Deinit_Network_Handler_Pool :: proc(pool: ^Network_Pool) {
	for handler in pool.container {
		Deinit_Tcp_Handler(handler)
	}
	delete(pool.container)
}

Create_Network_Handler :: proc(conn: net.TCP_Socket) -> ^Network_Tcp_Handler {
	new_handler := new(Network_Tcp_Handler)
	new_handler.conn = conn
	new_handler.operation_complete = false
	new_handler.bytes_transferred = 0
	new_handler.last_error = .Success
	return new_handler
}

Deinit_Tcp_Handler :: proc(handler: ^Network_Tcp_Handler) {
	if handler == nil do return
	net.close(handler.conn)
	free(handler)
}

/////////////////////////// Acceptor Handler Operations ///////////////////////////

Create_Acceptor_Handler :: proc(
	server_socket: net.TCP_Socket,
	event_loop: rawptr,
	callback: Acceptor_Callback,
	user_data: rawptr = nil,
) -> ^Acceptor_Handler {
	acceptor := new(Acceptor_Handler)
	acceptor.server_socket = server_socket
	acceptor.event_loop = event_loop
	acceptor.callback = callback
	acceptor.user_data = user_data
	acceptor.last_error = .Success
	return acceptor
}

Deinit_Acceptor_Handler :: proc(acceptor: ^Acceptor_Handler) {
	if acceptor == nil do return
	net.close(acceptor.server_socket)
	free(acceptor)
}

accept_connection :: proc(acceptor: ^Acceptor_Handler) -> Handler_Action {
	if acceptor == nil {
		return .Deinit
	}

	client_socket, _, accept_err := net.accept(acceptor.server_socket)

	if accept_err != nil {
		err_code := error_c.Net_Error_To_Error_Code(accept_err)

		if err_code == .Would_Block || err_code == .Try_Again {
			// No connection ready yet, continue waiting
			return .None
		}

		acceptor.last_error = err_code
		if acceptor.callback != nil {
			acceptor.callback(acceptor.user_data, {}, err_code, .Error)
		}
		return .Deinit
	}

	// Set new connection to non-blocking
	if err := set_socket_non_blocking(client_socket); err != .Success {
		acceptor.last_error = err
		net.close(client_socket)
		if acceptor.callback != nil {
			acceptor.callback(acceptor.user_data, {}, err, .Error)
		}
		return .None
	}

	// Call callback with new connection
	if acceptor.callback != nil {
		acceptor.callback(acceptor.user_data, client_socket, .Success, .Active)
	}

	return .None
}

/////////////////////////// Socket Utilities ///////////////////////////

set_socket_non_blocking :: proc(socket: net.TCP_Socket) -> error_c.Error_Code {
	sock_fd := cast(i32)socket
	flags := posix.fcntl(sock_fd, posix.F_GETFL, 0)
	if flags < 0 {
		return errno_to_error_code(posix.errno())
	}

	if posix.fcntl(sock_fd, posix.F_SETFL, flags | posix.O_NONBLOCK) < 0 {
		return errno_to_error_code(posix.errno())
	}

	return .Success
}

/////////////////////////// Async Read/Write Operations ///////////////////////////

Read_Tcp_Handler :: proc(
	tcp_handler: ^Network_Tcp_Handler,
	callback: Callback_Handler,
	user_data: rawptr = nil,
) -> error_c.Error_Code {
	if tcp_handler == nil {
		return .Invalid_Argument
	}

	// Set socket to non-blocking
	if err := set_socket_non_blocking(tcp_handler.conn); err != .Success {
		return err
	}

	tcp_handler.user_data = user_data
	tcp_handler.bytes_transferred = 0
	tcp_handler.operation_complete = false

	n_read, net_err := net.recv_tcp(tcp_handler.conn, tcp_handler.buffer[:])

	if net_err != nil {
		err_code := error_c.Net_Error_To_Error_Code(net_err)

		// No data available right now, but socket is alive
		if err_code == .Would_Block || err_code == .Try_Again {
			tcp_handler.last_error = .Success
			return .Success
		}

		// Real error occurred
		tcp_handler.last_error = err_code
		if callback != nil {
			callback(user_data, tcp_handler.buffer[:], 0, err_code, .Error)
		}
		return err_code
	}

	if n_read == 0 {
		tcp_handler.last_error = .End_Of_File
		tcp_handler.operation_complete = true
		if callback != nil {
			callback(user_data, tcp_handler.buffer[:], 0, .End_Of_File, .Deinit)
		}
		return .End_Of_File
	}

	tcp_handler.bytes_transferred = n_read
	tcp_handler.operation_complete = true
	tcp_handler.last_error = .Success

	if callback != nil {
		callback(user_data, tcp_handler.buffer[:n_read], n_read, .Success, .Active)
	}

	return .Success
}

Write_Tcp_Handler :: proc(
	tcp_handler: ^Network_Tcp_Handler,
	data: []byte,
	callback: Callback_Handler,
	user_data: rawptr = nil,
) -> error_c.Error_Code {
	if tcp_handler == nil || len(data) == 0 {
		return .Invalid_Argument
	}

	if err := set_socket_non_blocking(tcp_handler.conn); err != .Success {
		return err
	}

	tcp_handler.user_data = user_data
	tcp_handler.bytes_transferred = 0
	tcp_handler.operation_complete = false

	n_written, net_err := net.send_tcp(tcp_handler.conn, data)

	if net_err != nil {
		err_code := error_c.Net_Error_To_Error_Code(net_err)

		if err_code == .Would_Block || err_code == .Try_Again {
			tcp_handler.last_error = .Success
			return .Success
		}

		tcp_handler.last_error = err_code
		if callback != nil {
			callback(user_data, data, 0, err_code, .Error)
		}
		return err_code
	}

	tcp_handler.bytes_transferred = n_written
	tcp_handler.operation_complete = n_written == len(data)
	tcp_handler.last_error = .Success

	if callback != nil {
		state := State.Active if tcp_handler.operation_complete else State.Nothing
		callback(user_data, data[:n_written], n_written, .Success, state)
	}

	return .Success
}

echo :: proc(
	tcp_handler: ^Network_Tcp_Handler,
	event_type: Epoll_Event_Type,
	callback: Callback_Handler,
) -> Handler_Action {
	if tcp_handler == nil {
		return .Deinit
	}

	switch event_type {
	case .In:
		err := Read_Tcp_Handler(tcp_handler, callback, tcp_handler.user_data)

		if err == .End_Of_File {
			return .Deinit
		}

		if err != .Success && err != .Would_Block && err != .Try_Again {
			return .Deinit
		}

		// Check for exit command
		if tcp_handler.bytes_transferred > 0 {
			data := tcp_handler.buffer[:tcp_handler.bytes_transferred]
			if slice.equal(data, transmute([]u8)string("exit\r\n")) {
				return .Server_Shutdown
			}
		}

	case .Out:
		if tcp_handler.bytes_transferred > 0 {
			data := tcp_handler.buffer[:tcp_handler.bytes_transferred]
			err := Write_Tcp_Handler(tcp_handler, data, callback, tcp_handler.user_data)

			if err != .Success && err != .Would_Block && err != .Try_Again {
				return .Deinit
			}
		}

	case .Error:
		return .Deinit
	}

	return .None
}

main :: proc() {
	pool: Network_Pool
	handler := Create_Network_Handler()
	Init_Network_HandlerPool(&pool)
	append(&pool.container, handler)
}
