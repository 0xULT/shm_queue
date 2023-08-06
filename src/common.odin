package shm_queue

import "core:intrinsics"

@private
CACHE_LINE_PADDING :: 64
CACHE_LINE_PADDING_64PRIOR :: CACHE_LINE_PADDING - size_of(u64)
CACHE_LINE_PADDING_32PRIOR :: CACHE_LINE_PADDING - size_of(u32)

#assert(CACHE_LINE_PADDING_64PRIOR >= 0)
#assert(CACHE_LINE_PADDING_32PRIOR >= 0)

cas     :: intrinsics.atomic_compare_exchange_strong
load    :: intrinsics.atomic_load
store   :: intrinsics.atomic_store
relax   :: intrinsics.cpu_relax
add     :: intrinsics.atomic_add

@private
round_up_to_power_2 :: proc(c: u64) -> u64 {
    i : u64
    for i = 0; (1 << i) < c; i += 1 {}

	return 1 << i
}

ErrorSMQ :: enum u8 {
    none,
    full,
    empty,
    raced,
    not_ready,
    closed
}

get :: proc{get_mpmc, get_spsc}
put :: proc{put_mpmc, put_spsc}
free :: proc{free_mpmc, free_spsc}
is_closed :: proc{is_closed_mpmc, is_closed_spsc}
close :: proc{close_mpmc, close_spsc}
