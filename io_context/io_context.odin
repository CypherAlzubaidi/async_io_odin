package network_handler

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

/////////////////////////// Error Code System (ASIO-like) ///////////////////////////

Error_Code :: enum {
	Success = 0,
	// Connection errors
	Connection_Aborted,
	Connection_Refused,
	Connection_Reset,
	Not_Connected,
	Already_Connected,
	// I/O errors
	Would_Block,
	Try_Again,
	Operation_Canceled,
	Timed_Out,
	// Network errors
	Network_Down,
	Network_Unreachable,
	Host_Unreachable,
	// Resource errors
	No_Memory,
	No_Buffer_Space,
	Too_Many_Files,
	// Socket errors
	Bad_File_Descriptor,
	Invalid_Argument,
	Broken_Pipe,
	Message_Too_Large,
	// Protocol errors
	Protocol_Error,
	Wrong_Protocol_Type,
	Address_In_Use,
	Address_Not_Available,
	// System errors
	Access_Denied,
	Interrupted,
	Fault,
	// EOF
	End_Of_File,
	// Unknown
	Unknown,
}

Error_Category :: enum {
	System,
	Network,
	Application,
}

Error_Info :: struct {
	code:     Error_Code,
	category: Error_Category,
	message:  string,
}

// Convert net.Network_Error to Error_Code
net_error_to_error_code :: proc(err: net.Network_Error) -> Error_Code {
	switch err {
	case .None:
		return .Success
	case .Would_Block:
		return .Would_Block
	case .Connection_Aborted:
		return .Connection_Aborted
	case .Connection_Refused:
		return .Connection_Refused
	case .Connection_Reset:
		return .Connection_Reset
	case .Not_Connected:
		return .Not_Connected
	case .Timed_Out:
		return .Timed_Out
	case .Address_In_Use:
		return .Address_In_Use
	case .Broken_Pipe:
		return .Broken_Pipe
	case:
		return .Unknown
	}
}

// Convert errno to Error_Code
errno_to_error_code :: proc(errno: posix.Errno) -> Error_Code {
	switch errno {
	case .NONE:
		return .Success
	case .EAGAIN, .EWOULDBLOCK:
		return .Would_Block
	case .ECONNABORTED:
		return .Connection_Aborted
	case .ECONNREFUSED:
		return .Connection_Refused
	case .ECONNRESET:
		return .Connection_Reset
	case .ENOTCONN:
		return .Not_Connected
	case .ETIMEDOUT:
		return .Timed_Out
	case .ENETDOWN:
		return .Network_Down
	case .ENETUNREACH:
		return .Network_Unreachable
	case .EHOSTUNREACH:
		return .Host_Unreachable
	case .ENOMEM:
		return .No_Memory
	case .ENOBUFS:
		return .No_Buffer_Space
	case .EMFILE, .ENFILE:
		return .Too_Many_Files
	case .EBADF:
		return .Bad_File_Descriptor
	case .EINVAL:
		return .Invalid_Argument
	case .EPIPE:
		return .Broken_Pipe
	case .EMSGSIZE:
		return .Message_Too_Large
	case .EPROTONOSUPPORT:
		return .Wrong_Protocol_Type
	case .EADDRINUSE:
		return .Address_In_Use
	case .EADDRNOTAVAIL:
		return .Address_Not_Available
	case .EACCES:
		return .Access_Denied
	case .EINTR:
		return .Interrupted
	case .EFAULT:
		return .Fault
	case:
		return .Unknown
	}
}

get_error_message :: proc(code: Error_Code) -> string {
	switch code {
	case .Success:
		return "Success"
	case .Connection_Aborted:
		return "Connection aborted"
	case .Connection_Refused:
		return "Connection refused"
	case .Connection_Reset:
		return "Connection reset by peer"
	case .Not_Connected:
		return "Transport endpoint is not connected"
	case .Already_Connected:
		return "Transport endpoint is already connected"
	case .Would_Block:
		return "Operation would block"
	case .Try_Again:
		return "Try again"
	case .Operation_Canceled:
		return "Operation canceled"
	case .Timed_Out:
		return "Connection timed out"
	case .Network_Down:
		return "Network is down"
	case .Network_Unreachable:
		return "Network is unreachable"
	case .Host_Unreachable:
		return "No route to host"
	case .No_Memory:
		return "Out of memory"
	case .No_Buffer_Space:
		return "No buffer space available"
	case .Too_Many_Files:
		return "Too many open files"
	case .Bad_File_Descriptor:
		return "Bad file descriptor"
	case .Invalid_Argument:
		return "Invalid argument"
	case .Broken_Pipe:
		return "Broken pipe"
	case .Message_Too_Large:
		return "Message too long"
	case .Protocol_Error:
		return "Protocol error"
	case .Wrong_Protocol_Type:
		return "Protocol wrong type for socket"
	case .Address_In_Use:
		return "Address already in use"
	case .Address_Not_Available:
		return "Cannot assign requested address"
	case .Access_Denied:
		return "Permission denied"
	case .Interrupted:
		return "Interrupted system call"
	case .Fault:
		return "Bad address"
	case .End_Of_File:
		return "End of file"
	case .Unknown:
		return "Unknown error"
	}
	return "Undefined error"
}

make_error_info :: proc(code: Error_Code, category: Error_Category) -> Error_Info {
	return Error_Info{code = code, category = category, message = get_error_message(code)}
}

/////////////////////////// State and Handler Types ///////////////////////////

@(private)
State :: enum {
	Nothing,
	Active,
	Deinit,
	Error,
}

@(private)
Handler_Type :: enum {
	Recv,
	Send,
	Acceptor,
}

/////////////////////////// Callback Signatures ///////////////////////////

// Called when bind operation completes - user handles container storage here
Callback_Bind :: proc(socket: net.TCP_Socket, buffer: []byte, bytes_transferred: int, ec: Error_Code, container: rawptr)

// Called when network handler operation completes
Callback_Handler :: proc(data: rawptr, buffer: []byte, bytes_transferred: int, ec: Error_Code, state: State)

// Called when handler stops
Callback_Stop :: proc(data: rawptr)

// Called when acceptor receives connection
Acceptor_Callback :: proc(data: rawptr, socket: net.TCP_Socket, ec: Error_Code, state: State)

/////////////////////////// Data Structures ///////////////////////////

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
	last_error:         Error_Code,
	user_data:          rawptr,
	container:          rawptr,
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

Create_Network_Handler :: proc(conn: net.TCP_Socket, container: rawptr = nil) -> ^Network_Tcp_Handler {
	new_handler := new(Network_Tcp_Handler)
	new_handler.conn = conn
	new_handler.operation_complete = false
	new_handler.bytes_transferred = 0
	new_handler.last_error = .Success
	new_handler.container = container
	return new_handler
}

Deinit_Tcp_Handler :: proc(handler: ^Network_Tcp_Handler) {
	if handler == nil do return
	net.close(handler.conn)
	free(handler)
}

/////////////////////////// Socket Utilities ///////////////////////////

set_socket_non_blocking :: proc(socket: net.TCP_Socket) -> Error_Code {
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

// Async read operation with callback and container support
Read_Tcp_Handler :: proc(
	tcp_handler: ^Network_Tcp_Handler,
	callback: Callback_Handler,
	user_data: rawptr = nil,
	bind_callback: Callback_Bind = nil,
) -> Error_Code {
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

	// Attempt immediate read
	n_read, net_err := net.recv_tcp(tcp_handler.conn, tcp_handler.buffer[:])

	if net_err != nil {
		err_code := net_error_to_error_code(net_err)

		// Would block is expected for async operations
		if err_code == .Would_Block || err_code == .Try_Again {
			// Operation will complete later via epoll/kqueue
			tcp_handler.last_error = .Success
			return .Success
		}

		// Real error occurred
		tcp_handler.last_error = err_code
		if callback != nil {
			callback(user_data, tcp_handler.buffer[:], 0, err_code, .Error)
		}
		if bind_callback != nil {
			bind_callback(tcp_handler.conn, tcp_handler.buffer[:], 0, err_code, tcp_handler.container)
		}
		return err_code
	}

	// Check for EOF
	if n_read == 0 {
		tcp_handler.last_error = .End_Of_File
		tcp_handler.operation_complete = true
		if callback != nil {
			callback(user_data, tcp_handler.buffer[:], 0, .End_Of_File, .Deinit)
		}
		if bind_callback != nil {
			bind_callback(tcp_handler.conn, tcp_handler.buffer[:], 0, .End_Of_File, tcp_handler.container)
		}
		return .End_Of_File
	}

	// Successful immediate read
	tcp_handler.bytes_transferred = n_read
	tcp_handler.operation_complete = true
	tcp_handler.last_error = .Success

	// Call user callbacks - user handles container storage in bind_callback
	if callback != nil {
		callback(user_data, tcp_handler.buffer[:n_read], n_read, .Success, .Active)
	}
	if bind_callback != nil {
		bind_callback(tcp_handler.conn, tcp_handler.buffer[:n_read], n_read, .Success, tcp_handler.container)
	}

	return .Success
}

// Async write operation with callback
Write_Tcp_Handler :: proc(
	tcp_handler: ^Network_Tcp_Handler,
	data: []byte,
	callback: Callback_Handler,
	user_data: rawptr = nil,
) -> Error_Code {
	if tcp_handler == nil || len(data) == 0 {
		return .Invalid_Argument
	}

	// Set socket to non-blocking
	if err := set_socket_non_blocking(tcp_handler.conn); err != .Success {
		return err
	}

	tcp_handler.user_data = user_data
	tcp_handler.bytes_transferred = 0
	tcp_handler.operation_complete = false

	// Attempt immediate write
	n_written, net_err := net.send_tcp(tcp_handler.conn, data)

	if net_err != nil {
		err_code := net_error_to_error_code(net_err)

		// Would block is expected for async operations
		if err_code == .Would_Block || err_code == .Try_Again {
			tcp_handler.last_error = .Success
			return .Success
		}

		// Real error occurred
		tcp_handler.last_error = err_code
		if callback != nil {
			callback(user_data, data, 0, err_code, .Error)
		}
		return err_code
	}

	// Successful write
	tcp_handler.bytes_transferred = n_written
	tcp_handler.operation_complete = n_written == len(data)
	tcp_handler.last_error = .Success

	if callback != nil {
		state := State.Active if tcp_handler.operation_complete else State.Nothing
		callback(user_data, data[:n_written], n_written, .Success, state)
	}

	return .Success
}

/////////////////////////// Example Usage ///////////////////////////

example_read_callback :: proc(data: rawptr, buffer: []byte, bytes_transferred: int, ec: Error_Code, state: State) {
	if ec != .Success {
		fmt.printfln("Read error: %s", get_error_message(ec))
		return
	}

	fmt.printfln("Received %d bytes: %s", bytes_transferred, string(buffer[:bytes_transferred]))

	if state == .Deinit {
		fmt.println("Connection closed")
	}
	package network_handler

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

/////////////////////////// Error Code System (ASIO-like) ///////////////////////////

Error_Code :: enum {
		Success = 0,
		// Connection errors
		Connection_Aborted,
		Connection_Refused,
		Connection_Reset,
		Not_Connected,
		Already_Connected,
		// I/O errors
		Would_Block,
		Try_Again,
		Operation_Canceled,
		Timed_Out,
		// Network errors
		Network_Down,
		Network_Unreachable,
		Host_Unreachable,
		// Resource errors
		No_Memory,
		No_Buffer_Space,
		Too_Many_Files,
		// Socket errors
		Bad_File_Descriptor,
		Invalid_Argument,
		Broken_Pipe,
		Message_Too_Large,
		// Protocol errors
		Protocol_Error,
		Wrong_Protocol_Type,
		Address_In_Use,
		Address_Not_Available,
		// System errors
		Access_Denied,
		Interrupted,
		Fault,
		// EOF
		End_Of_File,
		// Unknown
		Unknown,
}

Error_Category :: enum {
		System,
		Network,
		Application,
}

Error_Info :: struct {
		code:     Error_Code,
		category: Error_Category,
		message:  string,
}

// Convert net.Network_Error to Error_Code
net_error_to_error_code :: proc(err: net.Network_Error) -> Error_Code {
		switch err {
		case .None:
			return .Success
		case .Would_Block:
			return .Would_Block
		case .Connection_Aborted:
			return .Connection_Aborted
		case .Connection_Refused:
			return .Connection_Refused
		case .Connection_Reset:
			return .Connection_Reset
		case .Not_Connected:
			return .Not_Connected
		case .Timed_Out:
			return .Timed_Out
		case .Address_In_Use:
			return .Address_In_Use
		case .Broken_Pipe:
			return .Broken_Pipe
		case:
			return .Unknown
		}
}

// Convert errno to Error_Code
errno_to_error_code :: proc(errno: posix.Errno) -> Error_Code {
		switch errno {
		case .NONE:
			return .Success
		case .EAGAIN, .EWOULDBLOCK:
			return .Would_Block
		case .ECONNABORTED:
			return .Connection_Aborted
		case .ECONNREFUSED:
			return .Connection_Refused
		case .ECONNRESET:
			return .Connection_Reset
		case .ENOTCONN:
			return .Not_Connected
		case .ETIMEDOUT:
			return .Timed_Out
		case .ENETDOWN:
			return .Network_Down
		case .ENETUNREACH:
			return .Network_Unreachable
		case .EHOSTUNREACH:
			return .Host_Unreachable
		case .ENOMEM:
			return .No_Memory
		case .ENOBUFS:
			return .No_Buffer_Space
		case .EMFILE, .ENFILE:
			return .Too_Many_Files
		case .EBADF:
			return .Bad_File_Descriptor
		case .EINVAL:
			return .Invalid_Argument
		case .EPIPE:
			return .Broken_Pipe
		case .EMSGSIZE:
			return .Message_Too_Large
		case .EPROTONOSUPPORT:
			return .Wrong_Protocol_Type
		case .EADDRINUSE:
			return .Address_In_Use
		case .EADDRNOTAVAIL:
			return .Address_Not_Available
		case .EACCES:
			return .Access_Denied
		case .EINTR:
			return .Interrupted
		case .EFAULT:
			return .Fault
		case:
			return .Unknown
		}
}

get_error_message :: proc(code: Error_Code) -> string {
		switch code {
		case .Success:
			return "Success"
		case .Connection_Aborted:
			return "Connection aborted"
		case .Connection_Refused:
			return "Connection refused"
		case .Connection_Reset:
			return "Connection reset by peer"
		case .Not_Connected:
			return "Transport endpoint is not connected"
		case .Already_Connected:
			return "Transport endpoint is already connected"
		case .Would_Block:
			return "Operation would block"
		case .Try_Again:
			return "Try again"
		case .Operation_Canceled:
			return "Operation canceled"
		case .Timed_Out:
			return "Connection timed out"
		case .Network_Down:
			return "Network is down"
		case .Network_Unreachable:
			return "Network is unreachable"
		case .Host_Unreachable:
			return "No route to host"
		case .No_Memory:
			return "Out of memory"
		case .No_Buffer_Space:
			return "No buffer space available"
		case .Too_Many_Files:
			return "Too many open files"
		case .Bad_File_Descriptor:
			return "Bad file descriptor"
		case .Invalid_Argument:
			return "Invalid argument"
		case .Broken_Pipe:
			return "Broken pipe"
		case .Message_Too_Large:
			return "Message too long"
		case .Protocol_Error:
			return "Protocol error"
		case .Wrong_Protocol_Type:
			return "Protocol wrong type for socket"
		case .Address_In_Use:
			return "Address already in use"
		case .Address_Not_Available:
			return "Cannot assign requested address"
		case .Access_Denied:
			return "Permission denied"
		case .Interrupted:
			return "Interrupted system call"
		case .Fault:
			return "Bad address"
		case .End_Of_File:
			return "End of file"
		case .Unknown:
			return "Unknown error"
		}
		return "Undefined error"
}

make_error_info :: proc(code: Error_Code, category: Error_Category) -> Error_Info {
		return Error_Info{code = code, category = category, message = get_error_message(code)}
}

/////////////////////////// State and Handler Types ///////////////////////////

@(private)
State :: enum {
		Nothing,
		Active,
		Deinit,
		Error,
}

@(private)
Handler_Type :: enum {
		Recv,
		Send,
		Acceptor,
}

/////////////////////////// Callback Signatures ///////////////////////////

// Called when bind operation completes - user handles container storage here
Callback_Bind :: proc(socket: net.TCP_Socket, buffer: []byte, bytes_transferred: int, ec: Error_Code, container: rawptr)

// Called when network handler operation completes
Callback_Handler :: proc(data: rawptr, buffer: []byte, bytes_transferred: int, ec: Error_Code, state: State)

// Called when handler stops
Callback_Stop :: proc(data: rawptr)

// Called when acceptor receives connection
Acceptor_Callback :: proc(data: rawptr, socket: net.TCP_Socket, ec: Error_Code, state: State)

/////////////////////////// Data Structures ///////////////////////////

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
		last_error:         Error_Code,
		user_data:          rawptr,
		container:          rawptr,
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

Create_Network_Handler :: proc(conn: net.TCP_Socket, container: rawptr = nil) -> ^Network_Tcp_Handler {
		new_handler := new(Network_Tcp_Handler)
		new_handler.conn = conn
		new_handler.operation_complete = false
		new_handler.bytes_transferred = 0
		new_handler.last_error = .Success
		new_handler.container = container
		return new_handler
}

Deinit_Tcp_Handler :: proc(handler: ^Network_Tcp_Handler) {
		if handler == nil do return
		net.close(handler.conn)
		free(handler)
}

/////////////////////////// Socket Utilities ///////////////////////////

set_socket_non_blocking :: proc(socket: net.TCP_Socket) -> Error_Code {
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

// Async read operation with callback and container support
Read_Tcp_Handler :: proc(
		tcp_handler: ^Network_Tcp_Handler,
		callback: Callback_Handler,
		user_data: rawptr = nil,
		bind_callback: Callback_Bind = nil,
) -> Error_Code {
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

		// Attempt immediate read
		n_read, net_err := net.recv_tcp(tcp_handler.conn, tcp_handler.buffer[:])

		if net_err != nil {
			err_code := net_error_to_error_code(net_err)

			// Would block is expected for async operations
			if err_code == .Would_Block || err_code == .Try_Again {
				// Operation will complete later via epoll/kqueue
				tcp_handler.last_error = .Success
				return .Success
			}

			// Real error occurred
			tcp_handler.last_error = err_code
			if callback != nil {
				callback(user_data, tcp_handler.buffer[:], 0, err_code, .Error)
			}
			if bind_callback != nil {
				bind_callback(tcp_handler.conn, tcp_handler.buffer[:], 0, err_code, tcp_handler.container)
			}
			return err_code
		}

		// Check for EOF
		if n_read == 0 {
			tcp_handler.last_error = .End_Of_File
			tcp_handler.operation_complete = true
			if callback != nil {
				callback(user_data, tcp_handler.buffer[:], 0, .End_Of_File, .Deinit)
			}
			if bind_callback != nil {
				bind_callback(tcp_handler.conn, tcp_handler.buffer[:], 0, .End_Of_File, tcp_handler.container)
			}
			return .End_Of_File
		}

		// Successful immediate read
		tcp_handler.bytes_transferred = n_read
		tcp_handler.operation_complete = true
		tcp_handler.last_error = .Success

		// Call user callbacks - user handles container storage in bind_callback
		if callback != nil {
			callback(user_data, tcp_handler.buffer[:n_read], n_read, .Success, .Active)
		}
		if bind_callback != nil {
			bind_callback(tcp_handler.conn, tcp_handler.buffer[:n_read], n_read, .Success, tcp_handler.container)
		}

		return .Success
}

// Async write operation with callback
Write_Tcp_Handler :: proc(
		tcp_handler: ^Network_Tcp_Handler,
		data: []byte,
		callback: Callback_Handler,
		user_data: rawptr = nil,
) -> Error_Code {
		if tcp_handler == nil || len(data) == 0 {
			return .Invalid_Argument
		}

		// Set socket to non-blocking
		if err := set_socket_non_blocking(tcp_handler.conn); err != .Success {
			return err
		}

		tcp_handler.user_data = user_data
		tcp_handler.bytes_transferred = 0
		tcp_handler.operation_complete = false

		// Attempt immediate write
		n_written, net_err := net.send_tcp(tcp_handler.conn, data)

		if net_err != nil {
			err_code := net_error_to_error_code(net_err)

			// Would block is expected for async operations
			if err_code == .Would_Block || err_code == .Try_Again {
				tcp_handler.last_error = .Success
				return .Success
			}

			// Real error occurred
			tcp_handler.last_error = err_code
			if callback != nil {
				callback(user_data, data, 0, err_code, .Error)
			}
			return err_code
		}

		// Successful write
		tcp_handler.bytes_transferred = n_written
		tcp_handler.operation_complete = n_written == len(data)
		tcp_handler.last_error = .Success

		if callback != nil {
			state := State.Active if tcp_handler.operation_complete else State.Nothing
			callback(user_data, data[:n_written], n_written, .Success, state)
		}

		return .Success
}

/////////////////////////// Example Usage ///////////////////////////

example_read_callback :: proc(data: rawptr, buffer: []byte, bytes_transferred: int, ec: Error_Code, state: State) {
		if ec != .Success {
			fmt.printfln("Read error: %s", get_error_message(ec))
			return
		}

		fmt.printfln("Received %d bytes: %s", bytes_transferred, string(buffer[:bytes_transferred]))

		// If success, store data in container (user's choice: dynamic array, queue, etc.)
		if data != nil {
			// Example 1: Store in dynamic array
			array := cast(^[dynamic]byte)data
			old_len := len(array)
			resize(array, old_len + bytes_transferred)
			copy(array[old_len:], buffer[:bytes_transferred])
			fmt.printfln("Stored in dynamic array, total size: %d", len(array))

			// Example 2: Store in queue (uncomment if using queue)
			// queue := cast(^Queue)data
			// for i in 0..<bytes_transferred {
			//     queue_push(queue, buffer[i])
			// }

			// Example 3: Store in circular buffer (uncomment if using circular buffer)
			// circ_buf := cast(^cb.Circular_Buffer)data
			// cb.write(circ_buf, buffer[:bytes_transferred])
		}

		if state == .Deinit {
			fmt.println("Connection closed")
		}
}

example_write_callback :: proc(data: rawptr, buffer: []byte, bytes_transferred: int, ec: Error_Code, state: State) {
		if ec != .Success {
			fmt.printfln("Write error: %s", get_error_message(ec))
			return
		}

		fmt.printfln("Sent %d bytes", bytes_transferred)
}

// Example usage with dynamic array as container
example_usage :: proc() {
		// Create your data container
		data_container: [dynamic]byte
		defer delete(data_container)

		// Create handler
		// handler := Create_Network_Handler(some_socket, &data_container)

		// Start async read - data_container will be passed as 'data' to callback
		 Read_Tcp_Handler(handler, example_read_callback, &data_container)

		fmt.println("Data will be stored in dynamic array inside the callback")
}
		return
	}

	fmt.printfln("Sent %d bytes", bytes_transferred)
}

// User handles container storage in bind callback
example_bind_callback_dynamic_array :: proc(socket: net.TCP_Socket, buffer: []byte, bytes_transferred: int, ec: Error_Code, container: rawptr) {
	if ec != .Success {
		fmt.printfln("Bind callback error: %s", get_error_message(ec))
		return
	}

	// User stores data in their container
	array := cast(^[dynamic]byte)container
	old_len := len(array)
	resize(array, old_len + bytes_transferred)
	copy(array[old_len:], buffer[:bytes_transferred])

	fmt.printfln("Stored %d bytes in dynamic array, total: %d", bytes_transferred, len(array))
}

example_bind_callback_queue :: proc(socket: net.TCP_Socket, buffer: []byte, bytes_transferred: int, ec: Error_Code, container: rawptr) {
	if ec != .Success {
		return
	}

	// User stores data in their queue
	// queue := cast(^Queue)container
	// for i in 0..<bytes_transferred {
	//     queue_push(queue, buffer[i])
	// }

	fmt.printfln("Stored %d bytes in queue", bytes_transferred)
}

example_bind_callback_circular_buffer :: proc(socket: net.TCP_Socket, buffer: []byte, bytes_transferred: int, ec: Error_Code, container: rawptr) {
	if ec != .Success {
		return
	}

	// User stores data in their circular buffer
	// circ_buf := cast(^cb.Circular_Buffer)container
	// cb.write(circ_buf, buffer[:bytes_transferred])

	fmt.printfln("Stored %d bytes in circular buffer", bytes_transferred)
}

// Example usage with dynamic array
example_usage_with_container :: proc() {
	// Create container
	data_container: [dynamic]byte
	defer delete(data_container)

	// Create handler with container
	// handler := Create_Network_Handler(some_socket, &data_container)

	// Start async read - user handles storage in bind callback
	// Read_Tcp_Handler(handler, example_read_callback, nil, example_bind_callback_dynamic_array)

	fmt.println("Example: User controls data storage in bind_callback")
}

// Example without container - just process data
example_usage_without_container :: proc() {
	// Create handler without container
	// handler := Create_Network_Handler(some_socket)

	// Start async read - just process data in callback
	// Read_Tcp_Handler(handler, example_read_callback, nil, nil)

	fmt.println("Example: Process data without storage")
}
