CC = gcc
NA = nasm
CFLAGS = -Wall -g
NFLAGS = -f elf64 -g -F dwarf
all: heap

heap: heap.o main.o
	$(CC) $(CFLAGS) -no-pie -o heap main.o heap.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

heap.o: heap.s
	$(NA) $(NFLAGS) heap.s

clean:
	rm -f *.o heap