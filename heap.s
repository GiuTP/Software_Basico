section .bss
heap_start: resq 1                          ; the beginning of the heap

section .text
global _setup_brk
global _dismiss_brk
global _memory_alloc
global _memory_free

; gets the current heap address
_setup_brk:
    push rbp
    mov rbp, rsp

    mov rax, 12                             ; sys_brk
    xor rdi, rdi
    syscall
    mov qword [heap_start], rax

    pop rbp
    ret

; resets the heap address to the beginning
_dismiss_brk:
    push rbp
    mov rbp, rsp

    mov rax, 12
    mov rdi, [heap_start]
    syscall

    pop rbp
    ret

_memory_alloc:
    push rbp
    mov rbp, rsp

    ; check if there's a free block 
    ; local variables: size_block, size_worst_block, ptr_worst_block and top_heap
    sub rsp, 32
    mov [rbp-8], rdi                        ; size_block
    mov QWORD [rbp-16], 0                   ; size_worst_block
    mov QWORD [rbp-24], 0                   ; ptr_worst_block

    mov rax, 12
    xor rdi, rdi    
    syscall 
    mov [rbp-32], rax                       ; top_heap (loop's ceil)

    mov rsi, [heap_start]                   ; i = beginning of heap

    _loop:  
        cmp rsi, [rbp-32]                   ; while i < top_heap
        jge _end_loop       

        cmp BYTE [rsi], 1                   ; if register[i]->valid == 1 then jump
        je _next_block  

        mov rdx, [rsi+1]                    ; rdx = register[i]->size_block
        cmp rdx, [rbp-8]                    ; if register[i]->size_block < size_block then jump
        jl _next_block  

        mov rdx, [rbp-16]                   ; rdx = size_worst_block
        cmp rdx, [rsi+1]                    ; if register[i]->size_block > size_worst_block then jump
        jg _next_block  

        mov rdx, [rsi+1]                    ; rdx = register[i]->size_block
        mov [rbp-16], rdx                   ; size_worst_block = register[i]->size_block
        mov [rbp-24], rsi                   ; ptr_worst_block = i
        _next_block:    
            mov rdx, [rsi+1]                ; rdx = register[i]->size_block
            add rsi, 9                  
            add rsi, rdx                    ; i++
            jmp _loop   
    _end_loop:  
        ; Case: there's a free block    
        mov rsi, [rbp-24]   
        cmp QWORD rsi, 0                    ; if ptr_worst_block == 0 then jump
        je _alloc_new_block 

        mov rdx, [rbp-16]   
        sub rdx, [rbp-8]                    ; extra_bytes = size_block - size_worst_block

        ; Case: there's enough and a extra space then split
        cmp rdx, 10                         ; if extra_bytes < 10 then jump
        jl _set_block   
        mov rbx, [rbp-8]                    ; rbx = size_block
        mov QWORD [rsi+1], rbx              ; register[ptr_worst_block]->size_block = size_block

        ; Create a new register 
        lea rbx, [rsi+9+rbx]                ; new_register
        mov BYTE [rbx], 0                   ; new_register->valid = 0
        sub rdx, 9                          
        mov QWORD [rbx+1], rdx              ; new_register->size_block = extra_bytes
    
        ; Case: there's enough and no extra space then return the block
        _set_block:
            mov BYTE [rsi], 1               ; register[ptr_worst_block]->valid = 1
            lea rax, [rsi+9]                ; return the address of the data's block
            jmp _exit_alloc

        ; Case: there's no free block
        _alloc_new_block:
            mov rax, 12                     ; sys_brk
            xor rdi, rdi                    ; reset rdi
            syscall                         ; call brk(0)

            mov rsi, rax                    ; beginning of new block
            mov rbx, [rbp-8]                ; rbx = size_block
            add rax, 9                      ; add the size of the header
            add rax, rbx                    ; add the size of the block
            mov rdi, rax                    ; new top of heap
            mov rax, 12                     ; sys_brk
            syscall                         ; call brk(new top of heap)
            
            mov BYTE [rsi], 1               ; set the block as allocate
            mov QWORD [rsi + 1], rbx        ; set the size of the block
            lea rax, [rsi+9]                ; return the address of the data's block

        _exit_alloc:
            add rsp, 32
            pop rbp
            ret

_memory_free:
    push rbp
    mov rbp, rsp

    cmp rdi, 0                              ; if ptr != 0(NULL) then jump
    jne _set_free
    mov rax, -1                             ; return -1
    jmp _exit_free

    _set_free:
        sub rdi, 9                          ; get the beginning of the register
        mov BYTE [rdi], 0                   ; register->valid = 0 (free)
        mov rax, 0                          ; return 0

    _exit_free:
        pop rbp
        ret