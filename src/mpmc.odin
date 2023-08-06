package shm_queue

import "core:c"

// 0: writable, 1: readable, 2: write ok, 3: read ok
@(private)
rwStatus :: enum u64 {
    writable,
    readable,
    write_ok,
    read_ok
}

@(private)
Item :: struct($D: typeid) {
    read_write: rwStatus,
    value:      D,
    _:          [CACHE_LINE_PADDING - (size_of(rwStatus) + size_of(D))%CACHE_LINE_PADDING]u8
}

MPMC :: struct($D: typeid) {
    cap:            u64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    cap_mod_mask:   u64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    head:           u64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    tail:           u64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    put_waits:      u64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    get_waits:      u64,
    _:              [CACHE_LINE_PADDING_64PRIOR]byte,
    done:           u32,
    _:              [CACHE_LINE_PADDING_32PRIOR]byte,
    data:           [dynamic]Item(D)
}

new_mpmc :: proc($T: typeid, capacity: u64) -> ^MPMC(T)
    where CACHE_LINE_PADDING - (size_of(rwStatus) + size_of(T))%CACHE_LINE_PADDING >= 0 {

    q := new(MPMC(T))

    sz := round_up_to_power_2(capacity)

    q.data = make([dynamic]Item(T), sz)
    q.cap = sz
    q.cap_mod_mask = sz - 1

    for i := u64(0); i < sz; i += 1 {
        q.data[i].read_write &= rwStatus.writable
    }

    return q
}

free_mpmc :: proc(q: ^MPMC($T)) {
    delete(q.data)
}

put_mpmc :: #force_inline proc(m: ^MPMC($I), item: I) -> ErrorSMQ {
    tail, head: u64
    holder: ^Item(I)

    for {
        head = load(&m.head)
        tail = load(&m.tail)
        nt := (tail + 1) & m.cap_mod_mask

        if nt == head {
            return ErrorSMQ.full
        }

        if head == tail && head == c.UINT64_MAX {
            return ErrorSMQ.not_ready
        }

        #no_bounds_check  holder = &m.data[tail]

        cas(&m.tail, tail, nt)
 
l:      for {
            if _, ok := cas(&holder.read_write, 
                rwStatus.writable, 
                rwStatus.write_ok); !ok {

                if load(&holder.read_write) == rwStatus.writable {
                    continue // retry our loop
                }

                // yield & restart our main loop
                relax()

                break l
            } else {
                holder.value = item

                if _, ok := cas(&holder.read_write, rwStatus.write_ok, rwStatus.readable); !ok {
                    return ErrorSMQ.raced
                }        

                return ErrorSMQ.none
            }
        }
    }
}

get_mpmc :: #force_inline proc(m: ^MPMC($I)) -> (I, ErrorSMQ) {
    if load(&m.done) == 1 {
        v : I
        return v, ErrorSMQ.closed
    }

    tail, head: u64
    holder: ^Item(I)

    for {
        head = load(&m.head)
        tail = load(&m.tail)

        if head == tail {
            v : I
            if head == c.UINT64_MAX {
                return v, ErrorSMQ.not_ready
            }

            return v, ErrorSMQ.empty
        }

        #no_bounds_check holder = &m.data[head]

        nh := (head + 1) & m.cap_mod_mask
        cas(&m.head, head, nh)

    l:
        for {
            if _, ok := cas(&holder.read_write, 
                rwStatus.readable, 
                rwStatus.read_ok); !ok {

                if load(&holder.read_write) == rwStatus.readable {
                    continue
                }

                relax()

                break l
            } else {
                if _, ok := cas(&holder.read_write, rwStatus.read_ok, rwStatus.writable); !ok {
                	v : I
                    return v, ErrorSMQ.raced
                }

                return holder.value, ErrorSMQ.none
            }
        }
    }
}

close_mpmc :: proc(m: ^MPMC($D)) {
    store(&m.done, 1)
}

is_closed_mpmc :: proc(m: ^MPMC($D)) -> bool {
    return load(&m.done) == 1
}
