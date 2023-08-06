package shm_queue

@(private)
HeaderSPSC :: struct {
    _:              [CACHE_LINE_PADDING]byte,
    write_cache:    i64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    write_idx:      i64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    read_cache:     i64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    read_idx:       i64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    done:           i32,
    _:              [CACHE_LINE_PADDING_32PRIOR]byte,
    mask:           i64,
    max_batch:      i64,
}

SPSC :: struct($T: typeid) {
    h:      HeaderSPSC,
    data:   [dynamic]T,
}

// version used for in memory only: only need one process to own this and then the pointer can be reused
new_spsc :: proc($T: typeid, capacity: u64) -> ^SPSC(T) {
    q := new(SPSC(T))

    sz := i64(round_up_to_power_2(capacity))

    q.data = make([dynamic]T, sz)
    q.h.mask = sz - 1
    q.h.max_batch = i64(round_up_to_power_2((1 << 8) - 1))

    return q
}

// clean up our allocations
free_spsc :: proc(q: ^SPSC($T)) {
    delete(q.data)
}

put_spsc :: #force_inline proc(s: ^SPSC($T), item: T) -> ErrorSMQ {
    write_cache := s.h.write_cache
    if masked, read_idx := write_cache - s.h.mask, load(&s.h.read_idx); masked >= read_idx {
        if write_cache > s.h.write_idx {
            store(&s.h.write_idx, write_cache)			
        }

        if read_idx = load(&s.h.read_idx); masked >= read_idx {
            return ErrorSMQ.full
        }
    }

    #no_bounds_check s.data[write_cache&s.h.mask] = item

    write_cache = add(&s.h.write_cache, 1)
    if write_cache - s.h.write_idx > s.h.max_batch {
        store(&s.h.write_idx, write_cache)
    }

    return ErrorSMQ.none
}

get_spsc :: #force_inline proc(s: ^SPSC($T)) -> (T, ErrorSMQ) {
    read_cache := s.h.read_cache
    if write_idx := load(&s.h.write_idx); read_cache >= write_idx {
        if read_cache > s.h.read_idx {
            store(&s.h.read_idx, read_cache)
        }
        if load(&s.h.done) == 1 {
            v : T
            return v, ErrorSMQ.closed
        }
        if write_idx = load(&s.h.write_cache); read_cache >= write_idx {
            v : T
            return v, ErrorSMQ.empty
        }
    }

    holder : T
    #no_bounds_check {
        holder = s.data[read_cache&s.h.mask]
    }

    read_cache += 1
    s.h.read_cache = read_cache
    if read_cache - s.h.read_idx > s.h.max_batch {
        store(&s.h.read_idx, read_cache)
    }

    return holder, ErrorSMQ.none
}

close_spsc :: proc(s: ^SPSC($T)) {
    store(&s.h.done, 1)
}

is_closed_spsc :: proc(s: ^SPSC($T)) -> bool {
    return load(&s.h.done) == 1
}
