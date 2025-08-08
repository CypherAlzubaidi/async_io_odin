package main

import "core:container/queue"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:slice"
import "core:sys/linux"

number_events_per_second :: 100

actions :: enum {
	server_shutdown,
	stop,
	nothing,
}

callback :: proc(data_: rawptr) -> actions
callback_deinit :: proc(data_: rawptr)


EventListener :: struct {
	data:               rawptr,
	callback_func:      callback,
	fd:                 linux.Fd,
	stop_callback_func: callback_deinit,
}


set_socket_non_blocking :: proc(cur_socket: net.TCP_Socket) {
	err := net.set_blocking(cur_socket, true)
	if (err != nil) {
		fmt.eprintfln(
			"there is freak error here idiot ,  prevent you from make socket non blocking  ",
		)
	}
}


accept_connection :: proc(connection: net.TCP_Socket) {

	listen_socket, listen_err := net.listen_tcp(
		net.Endpoint{port = 8000, address = net.IP4_Loopback},
	)
	if listen_err != nil {
		fmt.panicf("listen error : %s", listen_err)
	}

	// setting up socket for the client to connect to
	connection, client_endpoint, accept_err := net.accept_tcp(listen_socket)

	if accept_err != nil {
		fmt.panicf("%s", accept_err)
	}

	tcp_handler, init_err := init_tcp_handler(connection, 1)

	if init_err != nil {
		fmt.println(
			"failed to create connection idiot :) , you know why ? because your loser you don't want to skip the matrix ",
		)
		net.close(connection)
	}

	//register_new_fd()

}

////////////////////////////////////////////////////////// start tcp operation //////////////////////////////////////////////////////////


/*
this tcp handler to handle tcp connection
after the accept operation
*/
Tcp_operation :: struct {
	conn:         net.TCP_Socket,
	id:           uint,
	msgIn_queue:  queue.Queue(u8),
	msgOut_queue: queue.Queue(u8),
}


init_tcp_handler :: proc(conn: net.TCP_Socket, id: u32) -> (^Tcp_operation, os.Error) {
	handler_, any_error := mem.new(Tcp_operation)

	if any_error != nil {
		fmt.println("failed to allcate memory idiot :)")
		return nil, any_error
	}

	defer mem.free(handler_)

	set_socket_non_blocking(conn)

	handler_.conn = conn

	return handler_, any_error
}

routine :: proc(op_data: ^Tcp_operation) -> EventListener {

	deinit :: proc(op_data: rawptr) {
		cur_handler := cast(^Tcp_operation)op_data
		net.close(cur_handler.conn)
		mem.free(cur_handler)
	}

	return {
		data = op_data,
		callback_func = handle_tcp_operation,
		fd = cast(linux.Fd)op_data.conn,
		stop_callback_func = deinit,
	}
}

read :: proc(op_data: ^Tcp_operation) -> bool {
	buffer: [1024]byte
	_, err := net.recv(op_data.conn, buffer[:])

	if err != nil {
	}

	return false
}


write :: proc() {

}

handle_tcp_operation :: proc(data: rawptr) -> actions {
	return .nothing
}

////////////////////////////////////////////////////////// end tcp operation //////////////////////////////////////////////////////////


////////////////////////////////////////////////////////// Begin Event loop //////////////////////////////////////////////////////////
/*
this is like wrap of multiple varibles we will need it when we gonna
our program support multiple callbacks per file descriptor
*/
EventEntry :: struct {
	id:       u32,
	listener: EventListener,
}

Event_loop :: struct {
	epfd:              linux.Fd,
	fd_to_handler_map: map[linux.Fd][dynamic]EventEntry,
	id_counter:        u32,
	list_of_fd:        []linux.Fd,
	flag:              bool,
}

init_event_loop :: proc() -> Event_loop {
	epfd, epoll_error := linux.epoll_create1({.FDCLOEXEC})

	if epoll_error != nil {
		fmt.println("there is freak error here with epoll")
		return Event_loop{}
	}
	fd_to_handler_map := make_map(map[linux.Fd][dynamic]EventEntry)

	return Event_loop{epfd = epfd, fd_to_handler_map = fd_to_handler_map, id_counter = 0}
}

register_new_fd :: proc(event_loop: ^Event_loop, cur_sock: linux.Fd, listener: EventListener) {
	m := event_loop.fd_to_handler_map
	elem, ok := m[cur_sock]

	if !ok {
		elem = make([dynamic]EventEntry)
	}

	event_loop.id_counter += 1
	append(&elem, EventEntry{id = event_loop.id_counter, listener = listener})
	m[cur_sock] = elem
	event := linux.EPoll_Event {
		events = {.IN, .OUT, .ET},
		data = {fd = cur_sock},
	}

	error_ctl := linux.epoll_ctl(event_loop.epfd, .ADD, cur_sock, &event)

	if error_ctl != nil {
		fmt.println("hey idiot epoll ctl failed to add new event")
	}
}

delete_event_loop :: proc(event_loop: ^Event_loop) {
	m := event_loop.fd_to_handler_map
	for fd, entries in event_loop.fd_to_handler_map {
		for entry in entries {
			if entry.listener.stop_callback_func != nil {
				entry.listener.stop_callback_func(entry.listener.data)
			}
		}
		delete_dynamic_array(entries)
	}

	delete(event_loop.fd_to_handler_map)
	linux.close(event_loop.epfd)
}
/*
run_fdsp :: proc(even_loop: ^Event_loop) {

	/// container to store remove file descriptor
	fd_remove: [number_events_per_second]linux.Fd
	remove_counter: int = 0

	events: [number_events_per_second]linux.EPoll_Event
	nums_ready, wait_error := linux.epoll_wait(even_loop.epfd, &events[0], -1, -1)

	if (wait_error != nil) {
		fmt.println(
			"my frendo be cerful there isssssssss froking error here ok my frendo  , i love  you idiooooooooooooot",
		)
	}


}*/

delete_specific_fd_with_his_handler :: proc(
	event_loop: ^Event_loop,
	fd_remove: [number_events_per_second]linux.Fd,
	remove_counter: int,
) {
	current_fd: linux.Fd
	for i in 0 ..= remove_counter {
		current_fd = fd_remove[i]
		m := event_loop.fd_to_handler_map
		elements, ok := m[current_fd]

		if ok {
			for element in elements {
				if element.listener.stop_callback_func != nil {
					element.listener.stop_callback_func(element.listener.data)

					error_ctl := linux.epoll_ctl(event_loop.epfd, .ADD, current_fd, nil)

					if error_ctl != nil {
						fmt.println("hey idiot epoll ctl failed to delete the fd")
					}

				}
			}
			delete_dynamic_array(elements)
			linux.close(current_fd)
		}


	}

}

run_fds :: proc(event_loop: ^Event_loop) {

	/// container to store remove file descriptor
	fd_remove: [number_events_per_second]linux.Fd
	remove_counter: int = 0

	events: [number_events_per_second]linux.EPoll_Event
	nums_ready, wait_error := linux.epoll_wait(event_loop.epfd, &events[0], -1, -1)

	if (wait_error != nil) {
		fmt.println(
			"my frendo be cerful there isssssssss froking error here ok my frendo  , i love  you idiooooooooooooot",
		)
	}
	listener: linux.Fd
	action_status: actions
	for (!event_loop.flag) {
		for i in 0 ..= nums_ready {
			listener = events[i].data.fd
			m := event_loop.fd_to_handler_map
			elements, ok := m[listener]

			if ok {
				for element in elements {
					action_status = element.listener.callback_func(element.listener.data)

					if action_status == .stop {
						fd_remove[remove_counter] = listener
						remove_counter += 1
					}

					if action_status == .server_shutdown {
						event_loop.flag = true
					}
				}
			}

		}
	}
}


////////////////////////////////////////////////////////// End Event loop //////////////////////////////////////////////////////////


main :: proc() {
	event_loop := init_event_loop()
	defer delete_event_loop(&event_loop)
}
