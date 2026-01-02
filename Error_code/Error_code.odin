package Error_Code

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


Error_Code :: enum {
	Success = 0,
	Network_Unreachable,
	Insufficient_Resources,
	Invalid_Argument,
	Insufficient_Permissions,
	Broadcast_Not_Supported,
	Already_Connected,
	Already_Connecting,
	Already_Bound,
	Address_In_Use,
	Host_Unreachable,
	Refused,
	Reset,
	Connection_Closed,
	Not_Connected,
	Not_Listening,
	Unsupported_Socket,
	Aborted,
	Timeout,
	Would_Block,
	Interrupted,
	Port_Required,
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
Net_Error_To_Error_Code :: proc(err: net.Network_Error) -> Error_Code {
	switch err {
	case net.Create_Socket_Error.None:
		return .Success
	case net.Create_Socket_Error.Network_Unreachable:
		return .Network_Unreachable
	case net.Create_Socket_Error.Insufficient_Resources:
		return .Insufficient_Resources
	case net.Create_Socket_Error.Invalid_Argument:
		return .Invalid_Argument
	case net.Create_Socket_Error.Insufficient_Permissions:
		return .Insufficient_Permissions
	/////// Dial Error
	case net.Dial_Error.None:
		return .Success
	case net.Dial_Error.Network_Unreachable:
		return .Network_Unreachable
	case net.Dial_Error.Insufficient_Resources:
		return .Insufficient_Resources
	case net.Dial_Error.Invalid_Argument:
		return .Invalid_Argument
	case net.Dial_Error.Broadcast_Not_Supported:
		return .Broadcast_Not_Supported
	case net.Dial_Error.Already_Connected:
		return .Already_Connected
	case net.Dial_Error.Already_Connecting:
		return .Already_Connecting
	case net.Dial_Error.Address_In_Use:
		return .Address_In_Use
	case net.Dial_Error.Host_Unreachable:
		return .Host_Unreachable
	case net.Dial_Error.Refused:
		return .Refused
	case net.Dial_Error.Reset:
		return .Reset
	case net.Dial_Error.Timeout:
		return .Timeout
	case net.Dial_Error.Would_Block:
		return .Would_Block
	case net.Dial_Error.Interrupted:
		return .Interrupted
	case net.Dial_Error.Port_Required:
		return .Port_Required
	// Listen Error
	case net.Listen_Error.None:
		return .Success
	case net.Listen_Error.Network_Unreachable:
		return .Network_Unreachable
	case net.Listen_Error.Insufficient_Resources:
		return .Insufficient_Resources
	case net.Listen_Error.Invalid_Argument:
		return .Invalid_Argument
	case net.Listen_Error.Unsupported_Socket:
		return .Unsupported_Socket
	case net.Listen_Error.Already_Connected:
		return .Already_Connected
	case net.Listen_Error.Address_In_Use:
		return .Address_In_Use
	case net.Accept_Error.None:
		// Accept Error
		return .Success
	case net.Accept_Error.Network_Unreachable:
		return .Network_Unreachable
	case net.Accept_Error.Insufficient_Resources:
		return .Insufficient_Resources
	case net.Accept_Error.Invalid_Argument:
		return .Invalid_Argument
	case net.Accept_Error.Unsupported_Socket:
		return .Unsupported_Socket
	case net.Accept_Error.Not_Listening:
		return .Not_Listening
	case net.Accept_Error.Aborted:
		return .Aborted
	case net.Accept_Error.Timeout:
		return .Timeout
	case net.Accept_Error.Would_Block:
		return .Would_Block
	case net.Accept_Error.Interrupted:
		return .Interrupted
	// Bind Error
	case net.Bind_Error.None:
		return .Success
	case net.Bind_Error.Network_Unreachable:
		return .Network_Unreachable
	case net.Bind_Error.Insufficient_Resources:
		return .Insufficient_Resources
	case net.Bind_Error.Invalid_Argument:
		return .Invalid_Argument
	case net.Bind_Error.Already_Bound:
		return .Already_Bound
	case net.Bind_Error.Insufficient_Permissions_For_Address:
		return .Insufficient_Resources
	case net.Bind_Error.Address_In_Use:
		return .Address_In_Use
	// Tcp Send Error
	case net.TCP_Send_Error.None:
		return .Success
	case net.TCP_Send_Error.Network_Unreachable:
		return .Network_Unreachable
	case net.TCP_Send_Error.Insufficient_Resources:
		return .Insufficient_Resources
	case net.TCP_Send_Error.Invalid_Argument:
		return .Invalid_Argument
	case net.TCP_Send_Error.Connection_Closed:
		return .Connection_Closed
	case net.TCP_Send_Error.Not_Connected:
		return .Not_Connected
	case net.TCP_Send_Error.Host_Unreachable:
		return .Host_Unreachable
	case net.TCP_Send_Error.Timeout:
		return .Timeout
	case net.TCP_Send_Error.Would_Block:
		return .Would_Block
	case net.TCP_Send_Error.Interrupted:
		return .Interrupted
	// Tcp Recv Error
	case net.TCP_Recv_Error.None:
		return .Success
	case net.TCP_Recv_Error.Network_Unreachable:
		return .Network_Unreachable
	case net.TCP_Recv_Error.Insufficient_Resources:
		return .Insufficient_Resources
	case net.TCP_Recv_Error.Invalid_Argument:
		return .Invalid_Argument
	case net.TCP_Recv_Error.Not_Connected:
		return .Not_Connected
	case net.TCP_Recv_Error.Connection_Closed:
		return .Connection_Closed
	case net.TCP_Recv_Error.Timeout:
		return .Timeout
	case net.TCP_Recv_Error.Would_Block:
		return .Would_Block
	case net.TCP_Recv_Error.Interrupted:
		return .Interrupted
	// Set Socket non blocking
	case net.Set_Blocking_Error.None:
		return .Success
	case net.Set_Blocking_Error.Network_Unreachable:
		return .Network_Unreachable
	case net.Set_Blocking_Error.Invalid_Argument:
		return .Invalid_Argument
	case:
		return .Unknown
	}
}
/*
// Convert errno to Error_Code
Errno_To_Error_Code :: proc(errno: posix.Errno) -> Error_Code {
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
*/
get_error_message :: proc(code: Error_Code) -> string {
	switch code {
	case .Success:
		return "Success"
	case .Network_Unreachable:
		return "Network is unreachable"
	case .Insufficient_Resources:
		return "Insufficient resources (buffers or internal tables full)"
	case .Invalid_Argument:
		return "Invalid argument or socket option"
	case .Insufficient_Permissions:
		return "Insufficient permissions to perform this operation"
	case .Broadcast_Not_Supported:
		return "Broadcast is not supported on this socket"
	case .Already_Connected:
		return "Socket is already connected"
	case .Already_Connecting:
		return "Socket is already in the process of connecting"
	case .Already_Bound:
		return "Socket is already bound to an address"
	case .Address_In_Use:
		return "The address is already in use"
	case .Host_Unreachable:
		return "Could not reach the remote host"
	case .Refused:
		return "Connection refused by the remote host"
	case .Reset:
		return "Connection was reset by the remote host"
	case .Connection_Closed:
		return "The connection was closed/broken"
	case .Not_Connected:
		return "The socket is not connected"
	case .Not_Listening:
		return "The socket is not in a listening state"
	case .Unsupported_Socket:
		return "The socket type does not support this operation"
	case .Aborted:
		return "The connection was aborted"
	case .Timeout:
		return "The operation timed out"
	case .Would_Block:
		return "Non-blocking operation would block"
	case .Interrupted:
		return "Operation was interrupted (signal or cancellation)"
	case .Port_Required:
		return "Endpoint requires a port but none was provided"
	case .Unknown:
		return "An unknown or uncategorized error occurred"
	}
	return "Undefined error"
}

Make_Error_Info :: proc(code: Error_Code, category: Error_Category) -> Error_Info {
	return Error_Info{code = code, category = category, message = get_error_message(code)}
}
