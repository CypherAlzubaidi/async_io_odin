package memory_pool

import "core:fmt"

/*
 i don't why i called that memory pool in reality it's item pool
 :)
  item pool is very great it make my code for handling fd more simpler
  intead of using hashmap and loops
*/
@(private)
pool_error :: enum {
	nill_assgin,
}


memory_pool :: struct($Value: typeid) {
	elements:   [dynamic]Value,
	available:  [dynamic]int,
	some_value: Value,
}


add :: proc(p: ^memory_pool($Value)) -> (int, pool_error) {

	if (p == nil) {
		return -1, .nill_assgin
	}

	index: int
	m := p.elements
	n := p.available

	if len(p.available) > 0 {

		pop(&n) // => this pop function will pop last elem in dyanmic array
		return index, nil
	}
	f := p.some_value
	append(&m, f)
	return len(p.elements) - 1, nil

}

get :: proc(p: ^memory_pool($Value), id: int) -> ^Value {
	return &p.elements[id]
}

delete_pool :: proc(p: ^memory_pool($Value)) {
	delete(p.available)
	delete(p.elements)
}

release :: proc(p: ^memory_pool($Value), id: int) {
	append(&p.available, id)
}

what_is_type :: proc(p: ^memory_pool($Value)) {

	fmt.println("type of current memory pool is : ", Value)
}
