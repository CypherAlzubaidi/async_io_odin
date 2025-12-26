package network_handler

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


/////////////////////////// Bind Function or explaintion function callback ///////////////////////////


/////////////////////////// Bind Function or explaintion function callback ///////////////////////////

@(private)
Callback_bind :: proc(socket: net.TCP_Socket, buffer: [1024]u8, ec: Error_Code, container: ^$T)

/////////////////////////// Network Hnadler Callback (TCP) ///////////////////////////
@(private)
Callback_Handler :: proc(data: rawptr, buffer: [1024]u8, state: State)
@(private)
Callback_Stop :: proc(data: rawptr)

/////////////////////////// acceptor sturct callback ///////////////////////////

@(private)
acceptor_callback :: proc(data: rawptr, state: State) -> net.TCP_Socket
@(private)
acceptor_callback_stop :: proc(data: rawptr, state: State) -> net.TCP_Socket
