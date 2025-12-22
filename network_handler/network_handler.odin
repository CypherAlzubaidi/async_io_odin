package network_handler
import cb "../circular_buffer"
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
State :: enum {
	nothing,
	deinit,
}

@(private)


Handler_Type :: enum {
	recv,
	send,
	acceptor,
}


@(private)
Callback :: proc(data: rawptr, state: State)
@(private)
Callback_Stop :: proc(data: rawptr)

@(private)
acceptor_callback :: proc(data: rawptr, state: State) -> net.TCP_Socket
@(private)
acceptor_callback_stop :: proc(data: rawptr, state: State) -> net.TCP_Socket

@(private)
Callback_handler :: struct {
	/// callbakc function for tcp handler struct and everthing belong to it
	callback_func_1:      Callback,
	stop_callback_func_1: Callback_Stop,
	/// callbakc function for async accepotr struct and everthing belong to it
	data:                 rawptr,
	fd:                   linux.Fd,
	/// flag to check if current callback fn is compelete
	flag:                 bool,
	type:                 Handler_Type,
}

Network_Handler :: struct {
	conn:               net.TCP_Socket,
	operation_complete: bool,
	buffer:             [1024]u8,
}

create_network_handler :: proc(
	container: [dynamic]^Network_Handler,
	conn: net.TCP_Socket,
) -> ^Network_Handler {
	new_handler, err := mem.new(Network_Handler)

	if err != nil {
		fmt.println("errro said => ", err)
	}
	//set_socket_non_blocking(new_handler.conn)
	new_handler.conn = conn
	append(container, new_handler)
	append(&container, new_handler)
	return new_handler
}


create_handler_container :: proc() -> [dynamic]^Network_Handler {
	container := make([dynamic]^Network_Handler, context.temp_allocator)
	return container
}

deinit_tcp_handler :: proc(data: rawptr) {
	some_handler := cast(^Network_Handler)data
	net.close(some_handler.conn)
	free(some_handler)
}
