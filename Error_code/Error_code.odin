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
Net_Error_To_Error_Code :: proc(err: net.Network_Error) -> Error_Code {
	switch err {
	case .Success:
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

Make_Error_Info :: proc(code: Error_Code, category: Error_Category) -> Error_Info {
	return Error_Info{code = code, category = category, message = get_error_message(code)}
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
