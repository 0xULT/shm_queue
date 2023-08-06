package bench

import "core:fmt"
import "core:thread"
import "core:time"
import smq "../src"

thread_args :: struct($T: typeid) {
	q: T,
	num: i64
}

producer_spsc :: proc(t: ^thread.Thread) {
	d := cast(^thread_args(^smq.SPSC(i64)))(t.data)
	defer free(t.data)

	fmt.println("running producer - SPSC")

	num := d.num
	for i : i64 = 0; i < num; i += 1 {
		smq.put(d.q, i)
	}

	fmt.println("done producer - SPSC")
}

producer_mpmc :: proc(t: ^thread.Thread) {
	d := cast(^thread_args(^smq.MPMC(i64)))(t.data)
	defer free(t.data)

	fmt.println("running producer - MPMC")

	num := d.num
	for i : i64 = 0; i < num; i += 1 {
		smq.put(d.q, i)
	}

	fmt.println("done producer - MPMC")
}

consumer_spsc :: proc(t: ^thread.Thread) {
	cnt : i64
	err : smq.ErrorSMQ

	d := cast(^thread_args(^smq.SPSC(i64)))(t.data)
	defer free(d.q)

	fmt.println("running consumer - SPSC")

	// mark when we start
	start_t := time.now()
	
	num := d.num
l:	for cnt < num - 1 {
		switch cnt, err = smq.get(d.q); err {
		case .none, .empty:
    	case .full, .raced, .not_ready, .closed:
	    	fmt.println(err)
	    	break l
		}
	}

	// mark when we finish
	run_time := time.diff(start_t, time.now())

	fmt.println("done consumer - SPSC")

	fmt.printf("For %d elements it took %f ms (%d/sec) or %f ns/op\n", 
		num, 
		time.duration_milliseconds(run_time), 
		num*1e9/time.duration_nanoseconds(run_time),
		f64(time.duration_nanoseconds(run_time))/f64(num)  )
}

consumer_mpmc :: proc(t: ^thread.Thread) {
	cnt : i64
	err : smq.ErrorSMQ

	d := cast(^thread_args(^smq.MPMC(i64)))(t.data)
	defer free(d.q)

	fmt.println("running consumer - MPMC")

	// mark when we start
	start_t := time.now()
	
	num := d.num
l:	for cnt < num - 1 {
		switch cnt, err = smq.get(d.q); err {
		case .none, .empty:
    	case .full, .raced, .not_ready, .closed:
	    	fmt.println(err)
	    	break l
		}
	}

	// mark when we finish
	run_time := time.diff(start_t, time.now())

	fmt.println("done consumer - MPMC")

	fmt.printf("For %d elements it took %f ms (%d/sec or %f ns/op)\n", 
		num, 
		time.duration_milliseconds(run_time), 
		num*1e9/time.duration_nanoseconds(run_time),
		f64(time.duration_nanoseconds(run_time))/f64(num) )
}

time_spsc :: proc(num: i64) {
	q := smq.new_spsc(i64, 100_000)
	defer smq.free(q)

	time_transfers(q, num, producer_spsc, consumer_spsc)
}

time_mpmc :: proc(num: i64) {
	q := smq.new_mpmc(i64, 100_000)
	defer smq.free(q)

	time_transfers(q, num, producer_mpmc, consumer_mpmc)
}

time_transfers :: proc(q: $T, num: i64, consumer_proc, producer_proc: proc(t: ^thread.Thread)) {
	threads := make([dynamic]^thread.Thread, 0, 2)
	defer delete(threads)

	if t := thread.create(producer_proc); t != nil {
		t.init_context = context
		t.user_index = len(threads)

		d := new(thread_args(type_of(q)))
		d.num = num
		d.q = q

		t.data = d
		append(&threads, t)
		thread.start(t)
	}
	if t := thread.create(consumer_proc); t != nil {
		t.init_context = context
		t.user_index = len(threads)

		d := new(thread_args(type_of(q)))
		d.num = num
		d.q = q
		
		t.data = d

		append(&threads, t)
		thread.start(t)
	}

	fmt.println("starting spsc timing test")

	for len(threads) > 0 {
		for i := 0; i < len(threads); {
			if t := threads[i]; thread.is_done(t) {
				thread.destroy(t)

				ordered_remove(&threads, i)
			} else {
				i += 1
			}
		}
	}
}

main :: proc() {	
	time_spsc(5_000_000)
	time_mpmc(5_000_000)
}

