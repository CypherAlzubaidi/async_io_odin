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
Callback :: proc(data: rawptr, buffer: u8[1024], state: State)
@(private)
Callback_Stop :: proc(data: rawptr)

@(private)
acceptor_callback :: proc(data: rawptr, state: State) -> net.TCP_Socket
@(private)
acceptor_callback_stop :: proc(data: rawptr, state: State) -> net.TCP_Socket

@(private)
Data_Handler :: struct {
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

Network_Pool :: struct {
	container: [dynamic]^Network_Tcp_Handler,
}

Network_Tcp_Handler :: struct {
	conn:               net.TCP_Socket,
	operation_complete: bool,
	buffer:             [1024]u8,
}

Init_Network_HandlerPool :: proc(pool: ^Network_Pool) {
	pool.container = make([dynamic]^Network_Tcp_Handler, context.temp_allocator)
}

Create_Network_Handler :: proc(conn: net.TCP_Socket) -> ^Network_Tcp_Handler {
	new_handler, err := mem.new(Network_Handler)

	if err != nil {
		fmt.println("errro said => ", err)
	}
	//set_socket_non_blocking(new_handler.conn)
	new_handler.conn = conn
	return new_handler
}


Deinit_Tcp_Handler :: proc(data: rawptr) {
	some_handler := cast(^Network_Tcp_Handler)data
	net.close(some_handler.conn)
	free(some_handler)
}

Read_Tcp_Handler :: proc(tcp_handler: ^Network_Tcp_Handler) {

}

main :: proc() {
	pool: Network_Pool
	handler := Create_Network_Handler()
	Init_Network_HandlerPool(&pool)
	append(&pool.container, handler)

}
