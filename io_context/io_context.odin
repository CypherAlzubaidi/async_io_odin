package io_context
import error_c "../Error_code"
import mp "../memory_pool"
import "core:fmt"
import "core:sys/linux"

/////////////////////////// Types ///////////////////////////

Handler_Action :: enum {
	None,
	Deinit,
	Server_Shutdown,
}

Handler_Type :: enum {
	Recv,
	Send,
	Acceptor,
}

Callback_Func :: proc(data: rawptr) -> Handler_Action
Stop_Callback_Func :: proc(data: rawptr)

Callback_Handler :: struct {
	Data:                 rawptr,
	Callback_Func_1:      Callback_Func,
	Fd:                   linux.Fd,
	Stop_Callback_Func_1: Stop_Callback_Func,
	Type:                 Handler_Type,
}

Event_Loop :: struct {
	Epfd:       linux.Fd,
	Mem_Pool:   mp.memory_pool(Callback_Handler),
	Shutdown:   bool,
	Max_Events: int,
}

/////////////////////////// Task 1: Event Loop Lifecycle ///////////////////////////

Init_Event_Loop :: proc(max_events: int = 64) -> (^Event_Loop, error_c.Error_Code) {
	epfd, err := linux.epoll_create1({.CLOEXEC})

	if err != nil {
		fmt.println("error said => ", err)
		return nil, .Insufficient_Resources
	}

	loop := new(Event_Loop)
	loop.Epfd = epfd
	loop.Mem_Pool = mp.memory_pool(Callback_Handler){}
	loop.Shutdown = false
	loop.Max_Events = max_events

	return loop, .Success
}

Deinit_Event_Loop :: proc(loop: ^Event_Loop) {
	if loop == nil do return

	// Close epoll fd
	linux.close(loop.Epfd)

	// Clean up Memory Pool
	mp.delete_pool(&loop.Mem_Pool)

	free(loop)
}

/////////////////////////// Task 2: Async Network Procedures ///////////////////////////

Async_Read :: proc(
	loop: ^Event_Loop,
	fd: linux.Fd,
	data: rawptr,
	read_callback: Callback_Func,
	stop_callback: Stop_Callback_Func = nil,
) -> error_c.Error_Code {
	if loop == nil {
		return .Invalid_Argument
	}

	// Add to Memory Pool
	id, pool_err := mp.add(&loop.Mem_Pool)
	if pool_err != nil {
		return .Insufficient_Resources
	}

	// Setup Handler
	handler := mp.get(&loop.Mem_Pool, id)
	handler.Data = data
	handler.Callback_Func_1 = read_callback
	handler.Fd = fd
	handler.Stop_Callback_Func_1 = stop_callback
	handler.Type = .Recv

	// Epoll Registration
	event := linux.epoll_event {
		events = {.IN},
		data   = {u64 = cast(u64)id},
	}

	err := linux.epoll_ctl(loop.Epfd, .ADD, fd, &event)
	if err != nil {
		mp.release(&loop.Mem_Pool, id)
		return .Insufficient_Resources
	}

	return .Success
}

Async_Write :: proc(
	loop: ^Event_Loop,
	fd: linux.Fd,
	data: rawptr,
	write_callback: Callback_Func,
	stop_callback: Stop_Callback_Func = nil,
) -> error_c.Error_Code {
	if loop == nil {
		return .Invalid_Argument
	}

	// Add to Memory Pool
	id, pool_err := mp.add(&loop.Mem_Pool)
	if pool_err != nil {
		return .Insufficient_Resources
	}

	// Setup Handler
	handler := mp.get(&loop.Mem_Pool, id)
	handler.Data = data
	handler.Callback_Func_1 = write_callback
	handler.Fd = fd
	handler.Stop_Callback_Func_1 = stop_callback
	handler.Type = .Send

	// Epoll Registration
	event := linux.epoll_event {
		events = {.OUT},
		data   = {u64 = cast(u64)id},
	}

	err := linux.epoll_ctl(loop.Epfd, .ADD, fd, &event)
	if err != nil {
		mp.release(&loop.Mem_Pool, id)
		return .Insufficient_Resources
	}

	return .Success
}

Async_Accept :: proc(
	loop: ^Event_Loop,
	fd: linux.Fd,
	data: rawptr,
	accept_callback: Callback_Func,
	stop_callback: Stop_Callback_Func = nil,
) -> error_c.Error_Code {
	if loop == nil {
		return .Invalid_Argument
	}

	// Add to Memory Pool
	id, pool_err := mp.add(&loop.Mem_Pool)
	if pool_err != nil {
		return .Insufficient_Resources
	}

	// Setup Handler
	handler := mp.get(&loop.Mem_Pool, id)
	handler.Data = data
	handler.Callback_Func_1 = accept_callback
	handler.Fd = fd
	handler.Stop_Callback_Func_1 = stop_callback
	handler.Type = .Acceptor

	// Epoll Registration
	event := linux.epoll_event {
		events = {.IN},
		data   = {u64 = cast(u64)id},
	}

	err := linux.epoll_ctl(loop.Epfd, .ADD, fd, &event)
	if err != nil {
		mp.release(&loop.Mem_Pool, id)
		return .Insufficient_Resources
	}

	return .Success
}

/////////////////////////// Task 3: Core Run Logic ///////////////////////////

Run_Event_Loop :: proc(loop: ^Event_Loop) -> error_c.Error_Code {
	if loop == nil {
		return .Invalid_Argument
	}

	loop.Shutdown = false
	events := make([]linux.epoll_event, loop.Max_Events)
	defer delete(events)

	// Track handlers marked for removal
	to_remove := make([dynamic]int)
	defer delete(to_remove)

	for !loop.Shutdown {
		// Wait: Call epoll_wait to block until events occur
		n, err := linux.epoll_wait(loop.Epfd, raw_data(events), cast(i32)loop.Max_Events, -1)

		if err != nil {
			if err == .EINTR {
				continue
			}
			return .Unknown
		}

		// Clear removal list for this iteration
		clear(&to_remove)

		// Process: Iterate through returned events
		for i in 0 ..< n {
			event := events[i]

			// Retrieve Handler_Id from event.data
			handler_id := cast(int)event.data.u64

			// Get Handler from Memory Pool
			handler := mp.get(&loop.Mem_Pool, handler_id)

			if handler == nil || handler.Callback_Func_1 == nil {
				continue
			}

			// Execute Handler.Callback(Handler.Data)
			action := handler.Callback_Func_1(handler.Data)

			// Handle Return States
			switch action {
			case .Deinit:
				// Mark handler for removal
				append(&to_remove, handler_id)
			case .Server_Shutdown:
				// Set Event_Loop.Shutdown = true
				loop.Shutdown = true
			case .None:
				// Continue
			}
		}

		// Cleanup Phase: For every handler marked for removal
		for handler_id in to_remove {
			handler := mp.get(&loop.Mem_Pool, handler_id)

			if handler != nil {
				// Call epoll_ctl with .DEL
				linux.epoll_ctl(loop.Epfd, .DEL, handler.Fd, nil)

				// Execute Deinit function if it exists
				if handler.Stop_Callback_Func_1 != nil {
					handler.Stop_Callback_Func_1(handler.Data)
				}
			}

			// Release ID back to Memory Pool
			mp.release(&loop.Mem_Pool, handler_id)
		}
	}

	return .Success
}
