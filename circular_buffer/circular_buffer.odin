package circular_buffer

import "core:flags"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:slice"
import "core:sys/linux"

circular_buf :: struct($Value: typeid) {
	buffer:     []Value,
	size:       int,
	write:      int,
	counter:    int,
	some_value: Value,
}


create_circular_buf :: proc(size: int, $T: typeid) -> circular_buf(T) {
	same: circular_buf(T)
	/*
	 maybe later will have an isssue need a tissue
		that becasue allocate buf for each tcp handler that maybe will be bad idea
	*/
	buf: circular_buf(T)

	buf.buffer = make([]T, size)
	buf.size = size

	return buf

}


add :: proc(cb: ^circular_buf($Value), data: $T) {
	cb.buffer[cb.write] = data
	cb.write = (cb.write + 1) % cb.size

	if cb.counter < cb.size {
		cb.counter = cb.counter + 1
	}
}


dispatch :: proc(cb: ^circular_buf, $T: typeid) -> []T {

	result := make([]T, 0, cb.counter)

	for i in 0 ..< cb.counter {
		index := (cb.write + cb.size - cb.counter + i) % rb.size
		result = append(result, cb.buffer[index])
	}
	return result
}

len :: proc(cb: ^circular_buf) -> int {
	return cb.counter
}

@(private)
main :: proc() {
	fuck := create_circular_buf(1000, int)
	add(&fuck, 1)
	fmt.print(fuck.counter)
}
