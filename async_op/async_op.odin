package async_io_odin

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
/*
 async_read() => read_handler()
*/

// for handling our callback function state
@(private)

state :: enum {
	nothing,
	deinit,
}

@(private)

handler_type :: enum {
	recv,
	send,
	acceptor,
}

//////////////////////////// start event loop //////////////////////////////////
@(private)
EventEntry :: struct {
	fd:       linux.Fd,
	callback: callback_handler,
}

@(private)
Event_loop :: struct {
	epfd:     linux.Fd,
	mem_pool: ^mp.memory_pool(EventEntry),
	//id_counter : u32
	//list_of_fd : [dynamic]linux.Fd
}

@(private)
init_event_loop :: proc() -> Event_loop {
	epfd, err := linux.epoll_create1({.FDCLOEXEC})

	if err != nil {
		fmt.println("error said => ", err)
		return Event_loop{}

	}
	return Event_loop{epfd = epfd}
}

@(private)
run :: proc() {

}

//////////////////////////// end event loop //////////////////////////////////


//////////////////////////// start io context //////////////////////////////////


io_context :: struct {
	event_loop: Event_loop,
}


io_context_init :: proc() -> Event_loop {
	event_loop := init_event_loop()

	return event_loop
}

io_context_run :: proc() {

}

//////////////////////////// end io context //////////////////////////////////


error_io :: enum {
	operation_in_progress,
}
@(private)
set_socket_non_blocking :: proc(cur_socket: net.TCP_Socket) {
	//err := net.set_blocking(cur_socket, true)
	flag_ := posix.fcntl(cast(posix.FD)cur_socket, .GETFL, 0)

	if flag_ != 0 {
		fmt.println("there is problem with => posix.fcntl")
	}
	new_flags := flag_ | posix.O_NONBLOCK
	posix.fcntl(cast(posix.FD)cur_socket, .SETFL, 0)
}

@(private)
callback :: proc(data: rawptr, s: state)
@(private)
callback_stop :: proc(data: rawptr)

@(private)
acceptor_callback :: proc(data: rawptr, s: state) -> net.TCP_Socket
@(private)
acceptor_callback_stop :: proc(data: rawptr, s: state) -> net.TCP_Socket

@(private)
callback_handler :: struct {
	/// callbakc function for tcp handler struct and everthing belong to it
	callback_func_1:      callback,
	stop_callback_func_1: callback_stop,
	/// callbakc function for async accepotr struct and everthing belong to it
	//callback_func_2 : acceptor_callback ,
	//stop_callback_func_2 : acceptor_callback_stop ,
	data:                 rawptr,
	fd:                   linux.Fd,
	/// flag to check if current callback fn is compelete
	flag:                 bool,
	type:                 handler_type,
}


//////////////////////////// start tcp acceptor all thing associated with it  //////////////////////////////////


/// a client try connect to our server simualrtion
// server choose end poind
acceptor_handler :: struct {
	io_context_: io_context,
	end_point_1: net.Endpoint,
	end_point_2: net.Endpoint,
}
/*
@(private)

acceptor_hanlder :: proc(data_1 : rawptr , s : state){
 some_hanlder_1 := cast(^acceptor_handler)data_1
 }*/

/*
@(private)
accept_conn_from_acceptor:: proc(acceptor : ^acceptor_handler) -> tcp_handler{

    listen_socket , listen_err := net.listen_tcp(acceptor.end_point_1)

    if listen_err != nil {
        fmt.println("error said => " , listen_err)
    }

    }*/

async_acceptor :: proc(end_point : net.Endpoint) -> acceptor_handler{
    id, err := mp.add(context_.event_loop.mem_pool)
	defer mp.release(context_.event_loop.mem_pool, id)

	listen_socket, err := net.listen_tcp(end_point)
    if err != nil {
        return acceptor_handler{}
    }

	some_handler := callback_handler {
		data               = nil,
		callback_func_1      = nil,
		fd                 = listen_socket,
		stop_callback_func_1 = nil,
		type = .acceptor ,
	}

	mp.get(context_.event_loop.mem_pool, id).fd = listen_socket
	mp.get(context_.event_loop.mem_pool, id).callback = some_handler

	read_event := linux.EPoll_Event {
		events = {.OUT},
		data = {ptr = &id},
	}
	error_ctl := linux.epoll_ctl(
		context_.event_loop.epfd,
		.ADD,
		cast(linux.Fd)listen_socket,
		&read_event,
	)

	if error_ctl != nil {
		fmt.println("error said => ", error_ctl)
}



//////////////////////////// end tcp acceptor all thing associated with it  //////////////////////////////////




//////////////////////////// start tcp hanlder all thing associated with it  //////////////////////////////////


/// this called later tcp_handler
tcp_handler :: struct {
	conn:               net.TCP_Socket,
	operation_complete: bool,
	circular_buffer:    cb.circular_buf(u8),
	//buffer:             [1024 * 2]u8,
	//event_container:    [100]linux.EPoll_Event,
}

@(private)
int_tcp_hanlder :: proc(conn: net.TCP_Socket) -> ^tcp_handler {
	new_tcp_reader, err := mem.new(tcp_handler)

	if err != nil {
		fmt.println("errro said => ", err)
	}
	set_socket_non_blocking(conn)
	new_tcp_reader.conn = conn
	return new_tcp_reader
}

@(private)
init_cb_of_tcp_handler :: proc(handler: ^tcp_handler) {
	handler.circular_buffer = cb.create_circular_buf(1000, u8)
}

@(private)
deinit_tcp_handler :: proc(data: rawptr) {
	some_handler := cast(^tcp_handler)data
	net.close(some_handler.conn)
	free(some_handler)
}

@(private)
recv_handler :: proc(data: rawptr, s: state) {
	some_handler := cast(^tcp_handler)data
	read_data_from_socket(some_handler)
}

@(private)

send_handler :: proc(data: rawptr, s: state) {
	some_hanlder := cast(^tcp_handler)data
	send_data_from_socket(some_hanlder)
}

@(private)
create_tcp_handler :: proc(conn: net.TCP_Socket) -> ^tcp_handler {
	handler := int_tcp_hanlder(conn)
	init_cb_of_tcp_handler(handler)
	return handler
}

// this the function will be hanlde read
// operation behind scenes

@(private)
recv_data_from_socket :: proc(handler: ^tcp_handler) -> bool {
	temp_buffer: [1024]u8
	n_read, err := net.recv_tcp(handler.conn, temp_buffer[:])

	if err != nil {
		if err != .Would_Block {
			fmt.printfln("error said => ", err)
		}
	}

	for i in 0 ..< n_read {
		cb.add(&handler.circular_buffer, temp_buffer[i])
	}

	if n_read == 0 {
		return true
	}

	return false
}

send_data_from_socket :: proc(handler: ^tcp_handler) {
	data := cb.dispatch(&handler.circular_buffer, u8)

	n_write, err := net.send_tcp(handler.conn, data[:])

	if err != nil {
		fmt.println("error said => ", err)
	}
}

async_recv :: proc(conn: ^tcp_handler, context_: io_context) {
	//m := event_loop.container
	id, err := mp.add(context_.event_loop.mem_pool)
	defer mp.release(context_.event_loop.mem_pool, id)


	some_handler := callback_handler {
		data               = conn,
		callback_func_1      = recv_handler,
		fd                 = cast(linux.Fd)conn.conn,
		stop_callback_func_1 = deinit_tcp_handler,
		type = .recv ,
	}

	mp.get(context_.event_loop.mem_pool, id).fd = cast(linux.Fd)conn.conn
	mp.get(context_.event_loop.mem_pool, id).callback = some_handler

	read_event := linux.EPoll_Event {
		events = {.IN},
		data = {ptr = &id},
	}
	error_ctl := linux.epoll_ctl(
		context_.event_loop.epfd,
		.ADD,
		cast(linux.Fd)conn.conn,
		&read_event,
	)

	if error_ctl != nil {
		fmt.println("error said => ", error_ctl)
	}
}

async_send :: proc(conn: ^tcp_handler, context_: io_context) {
    id, err := mp.add(context_.event_loop.mem_pool)
	defer mp.release(context_.event_loop.mem_pool, id)


	some_handler := callback_handler {
		data               = conn,
		callback_func_1      = send_handler,
		fd                 = cast(linux.Fd)conn.conn,
		stop_callback_func_1 = deinit_tcp_handler,
		type = .send ,
	}

	mp.get(context_.event_loop.mem_pool, id).fd = cast(linux.Fd)conn.conn
	mp.get(context_.event_loop.mem_pool, id).callback = some_handler

	read_event := linux.EPoll_Event {
		events = {.OUT},
		data = {ptr = &id},
	}
	error_ctl := linux.epoll_ctl(
		context_.event_loop.epfd,
		.ADD,
		cast(linux.Fd)conn.conn,
		&read_event,
	)

	if error_ctl != nil {
		fmt.println("error said => ", error_ctl)

}



//////////////////////////// end tcp hanlder all thing associated with it  //////////////////////////////////




main :: proc(data: $T) {
	context.allocator
}
