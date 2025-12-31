package network_handler

import error_c "../Error_code"
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


// Called when network handler operation completes
Callback_Handler :: proc(
	data: rawptr,
	buffer: []byte,
	bytes_transferred: int,
	ec: error_c.Error_Code,
	state: State,
)

// Called when handler stops
Callback_Stop :: proc(data: rawptr)

// Called when acceptor receives connection
Acceptor_Callback :: proc(
	data: rawptr,
	socket: net.TCP_Socket,
	ec: error_c.Error_Code,
	state: State,
)
