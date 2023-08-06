
benchmark:
	odin build ./bench/main.odin -file -out:./bin/bench
	./bin/bench

clean:
	rm -rf ./bin/*
