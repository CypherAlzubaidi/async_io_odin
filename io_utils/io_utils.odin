package io_utils

import "core:mem"

Buffer :: proc {
	Buffer_From_Slice,
	Buffer_From_Dynamic,
	Buffer_From_Struct,
}

Buffer_From_Slice :: proc(data: []byte) -> []byte {
	return data
}

Buffer_From_Dynamic :: proc(data: ^[dynamic]byte) -> []byte {
	return data[:]
}

Buffer_From_Struct :: proc(data: ^$T) -> []byte {
	return mem.ptr_to_bytes(data, size_of(T))
}
