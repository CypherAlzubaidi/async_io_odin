package thread_pool
import "core:container/queue"
import "core:crypto/_aes/hw_intel"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:odin/printer"
import "core:os"
import "core:slice"
import "core:sync"
import "core:sys/linux"
import "core:sys/posix"
import "core:sys/unix"
import "core:thread"


Task_Handler :: proc(data: int)

Task :: struct {
	Task_: Task_Handler,
	data:  int,
}

Thread_pool :: struct {
	Worker_container: [dynamic]^Worker,
	count:            int,
	mtx:              sync.Atomic_Mutex,
	taskQueueCv:      sync.Atomic_Cond,
	allDoneCv:        sync.Atomic_Cond,
	tasks:            queue.Queue(Task),
	queue_task_num:   int,
}


init_tp :: proc(thread_pool: ^Thread_pool, num: int) {
	thread_pool.Worker_container = make([dynamic]^Worker, context.temp_allocator)
	thread_pool.count = num
	Create_Worker(thread_pool, num)
}


Run_Task :: proc(th: ^Thread_pool, task_: Task) {

	sync.atomic_mutex_lock(&th.mtx)
	defer sync.atomic_mutex_unlock(&th.mtx)
	queue.push_back(&th.tasks, task_)
	sync.atomic_cond_signal(&th.taskQueueCv)
}

Is_RunnningTasks :: proc(th: ^Thread_pool) -> bool {
	for i := 0; i < th.count; i += 1 {
		if (Is_Worker_busy(th.Worker_container[i])) {
			return true
		}
	}

	return false
}


Get_Task :: proc(th: ^Thread_pool) -> (task: Task, ok: bool) {


	sync.atomic_mutex_lock(&th.mtx)
	defer sync.atomic_mutex_unlock(&th.mtx)


	for (queue.len(th.tasks) != 0) {
		sync.atomic_cond_wait(&th.taskQueueCv, &th.mtx)
	}
	if queue.len(th.tasks) == 0 {
		//return {}, false
		sync.atomic_cond_broadcast(&th.allDoneCv)
		break
	}

	task = queue.front(&th.tasks)
	queue.pop_front(&th.tasks)
	th.count = th.count - 1
	return task, true
}

WaitFor_AllDone :: proc(th: ^Thread_pool) {

	sync.atomic_mutex_lock(&th.mtx)
	defer sync.atomic_mutex_unlock(&th.mtx)
	for (queue.len(th.tasks) == 0) {
		sync.atomic_cond_wait(&th.allDoneCv, &th.mtx)

	}

}

Worker :: struct {
	thread:  ^thread.Thread,
	mtx:     sync.Atomic_Mutex,
	cv:      sync.Atomic_Cond,
	isBusy:  bool,
	task:    ^Task,
	isDying: bool,
	pool:    ^Thread_pool,
}


Is_Worker_busy :: proc(worker: ^Worker) -> bool {

	return worker.isBusy

}
/*
Worker_SetJob :: proc(worker: ^Worker, task_: ^Task) {
	sync.atomic_mutex_lock(&worker.mtx)
	defer sync.atomic_mutex_unlock(&worker.mtx)
	worker.task = task_
	worker.isBusy = true
	sync.atomic_cond_signal(&worker.cv)
}
*/

Run_Worker_2 :: proc(th: ^thread.Thread) {
	worker := (cast(^Worker)th.data)
	sync.atomic_mutex_lock(&worker.mtx)
	defer sync.atomic_mutex_unlock(&worker.mtx)
	for (true) {
		for (worker.task != nil || worker.isDying) {
			sync.atomic_cond_wait(&worker.cv, &worker.mtx)
		}
		if (worker.isDying) {
			break
		}
		worker.task = nil
		worker.isBusy = false
	}

}


Run_Worker_1 :: proc(th: ^thread.Thread) {
	worker := (cast(^Worker)th.data)
	//sync.atomic_mutex_lock(&worker.mtx)
	//defer sync.atomic_mutex_unlock(&worker.mtx)
	task: Task
	ok: bool
	for {
		task, ok = Get_Task(worker.pool)
		/*
		if !ok {
			break
			}*/

		task.Task_(task.data)
	}
}


Worker_Kill :: proc() {

}

Worker_Join :: proc() {


}


Create_Worker :: proc(th: ^Thread_pool, num: int) {
	for i := 0; i < num; i += 1 {
		new_ptr := new(Worker, context.temp_allocator)
		new_ptr.isBusy = false
		new_thread := thread.create(Run_Worker_1)
		new_thread.data = new_ptr
		new_ptr.thread = new_thread
		new_ptr.isDying = false
		new_ptr.pool = th
		append(&th.Worker_container, new_ptr)
		new_ptr.task = nil
		thread.start(new_ptr.thread)

	}

}
