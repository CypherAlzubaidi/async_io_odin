package event_loop
import error_c "../Error_code"
import cb "../circular_buffer"
import io_u "../io_utils"
import mp "../memory_pool"
import "../network_handler"
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
Event_Entry :: struct {
	fd:       linux.Fd,
	callback: callback_handler,
}

@(private)
Event_loop :: struct {
	epfd:     linux.Fd,
	mem_pool: ^mp.memory_pool(Event_Entry),
	//id_counter : u32
	//list_of_fd : [dynamic]linux.Fd
}

@(private)
Init_Event_Loop :: proc() -> Event_loop {
	epfd, err := linux.epoll_create1({.FDCLOEXEC})

	if err != nil {
		fmt.println("error said => ", err)
		return Event_loop{}

	}
	return Event_loop{epfd = epfd}
}

@(private)
Run_Event_loop :: proc() {

}
