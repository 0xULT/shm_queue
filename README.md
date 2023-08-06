# Shared Memory Queue
- thread safe lock free ring buffers that seek to minimize false sharing
- shameless port of two Golang implementations
	- SPSC: `https://github.com/andy2046/gopie/blob/master/pkg/spsc/spsc.go`
	- MPMC: `https://github.com/hedzr/go-ringbuf/tree/master/mpmc`

# TODO
- add in memory mapped versions that allow for usage across different processes
