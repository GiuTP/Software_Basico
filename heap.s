section .note.GNU-stack progbits noalloc noexec nowrite

section .bss
heap_start: resq 1                          ; the beginning of the heap

section .text
global setup_brk
global dismiss_brk
global memory_alloc
global memory_free

; gets the current heap address
setup_brk:
    push rbp
    mov rbp, rsp

    mov rax, 12                             ; sys_brk
    xor rdi, rdi
    syscall
    mov qword [heap_start], rax

    pop rbp
    ret

; resets the heap address to the beginning
dismiss_brk:
    push rbp
    mov rbp, rsp

    mov rax, 12
    mov rdi, [heap_start]
    syscall

    pop rbp
    ret

memory_alloc:
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
        cmp rdx, [rsi+1]                    ; if size_worst_block > register[i]->size_block then jump
        jg _next_block  

        mov rdx, [rsi+1]                    ; rdx = register[i]->size_block
        mov [rbp-16], rdx                   ; size_worst_block = register[i]->size_block
        mov [rbp-24], rsi                   ; ptr_worst_block = i
        _next_block:    
            mov rdx, [rsi+1]                ; rdx = register[i]->size_block
            add rsi, 9                  
            add rsi, rdx                    ; i++
            add rsi, 8
            jmp _loop   
    _end_loop:  
        ; Case: there's a free block    
        mov rsi, [rbp-24]   
        cmp QWORD rsi, 0                    ; if ptr_worst_block == 0 then jump
        je _alloc_new_block 

        mov rdx, [rbp-16]   
        sub rdx, [rbp-8]                    ; extra_bytes = size_block - size_worst_block

        ; Case: there's enough and a extra space then split
        cmp rdx, 18                         ; if extra_bytes < 18 then jump
        jl _set_block   
        mov rbx, [rbp-8]                    ; rbx = size_block
        mov QWORD [rsi+1], rbx              ; register[ptr_worst_block]->size_block = size_block (header)
        mov QWORD [rsi+9+rbx], rbx          ; register[ptr_worst_block]->size_block = size_block (footer)

        ; Create a new register 
        lea rbx, [rsi+9+rbx+8]              ; new_register
        mov BYTE [rbx], 0                   ; new_register->valid = 0
        sub rdx, 17                          
        mov QWORD [rbx+1], rdx              ; new_register->size_block = extra_bytes (header)
        mov QWORD [rbx+9+rdx], rdx          ; new_register->size_block = extra_bytes (footer)
    
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
            add rax, 8                      ; add the size of the footer
            add rax, rbx                    ; add the size of the block
            mov rdi, rax                    ; new top of heap
            mov rax, 12                     ; sys_brk
            syscall                         ; call brk(new top of heap)
            
            mov BYTE [rsi], 1               ; set the block as allocate
            mov QWORD [rsi + 1], rbx        ; set the size of the block (header)
            mov QWORD [rsi + 9 + rbx], rbx  ; set the size of the block (footer)
            lea rax, [rsi+9]                ; return the address of the data's block

        _exit_alloc:
            add rsp, 32
            pop rbp
            ret

memory_free:
    push rbp
    mov rbp, rsp

    cmp rdi, 0                              ; if ptr != 0(NULL) then jump
    jne _set_free
    mov rax, -1                             ; return -1
    jmp _exit_free

    _set_free:
        sub rdi, 9                          ; get the beginning of the register
        mov BYTE [rdi], 0                   ; register->valid = 0 (free)
    ; Starting of the merge registers
    ; Check behind
        sub rsp, 32
        mov [rbp - 8], rdi                  ; ponteiro base 
        mov rax, [rdi + 1]
        mov [rbp - 16], rax                 ; tamanho do bloco inicial
        mov rax, [heap_start]
        mov [rbp - 24], rax                 ; inicio da heap
        mov rax, 12
        xor rdi, rdi
        syscall
        mov [rbp - 32], rax                 ; topo da heap
        xor rax, rax

    _loop_merge_behind:
        mov rdi, [rbp - 8]                  ; ponteiro do bloco atual
        sub rdi, 8                          ; endereco do tamanho do bloco anterior (footer)
        cmp rdi, [rbp - 24]                 ; Se o addr do footer for menor que o inicio da heap pula
        jle _loop_merge_ahead

        mov QWORD rdi, [rdi]                ; tamamnho do bloco anterior
        mov rdx, [rbp - 8]                  ; ponteiro base atual 
        sub rdx, 8                          ; ponteiro esta no inicio do footer
        sub rdx, rdi                        ; ponteiro esta no inicio da area de dados
        sub rdx, 9                          ; ponteiro esta no inicio do header (consequentemente comeco do bloco anterior)
        cmp BYTE [rdx], 1                   ; if bloco anterior ocupado pula
        je _loop_merge_ahead

        add rdi, [rbp - 16]                 ; rdi = size bloco anterior + size bloco atual
        add rdi, 17                         ; rdi = size bloco dados + metadados
        mov [rdx + 1], rdi                  ; tamanho novo = rdi
        mov [rdx + 9 + rdi], rdi            ; footer
        mov [rbp - 8], rdx                  ; novo ponteiro atual
        mov [rbp - 16], rdi                 ; novo tamanho atual
        jmp _loop_merge_behind
    
    _loop_merge_ahead:
        mov rdi, [rbp - 8]                  ; ponteiro do bloco atual
        mov rdx, [rdi + 1]                  ; tamanho do bloco atual
        lea rdx, [rdi + 9 + rdx + 8]        ; ponteiro do proximo bloco
        cmp rdx, [rbp - 32]                 ; Se o addr do header for maior ou igual ao topo da heap pula
        jge _shrink_heap

        cmp BYTE [rdx], 1                   ; Se proximo bloco estiver ocupado pula
        je _shrink_heap

        mov rdx, [rdx + 1]                  ; tamanho do proximo bloco
        add rdx, [rbp - 16]                 ; rdx = tamanho atual + tamanho proximo
        add rdx, 17                         ; rdx = tamanho dados + tamanho metadados
        mov [rdi + 1], rdx                  ; tamanho novo = rdx
        mov [rdi + 9 + rdx], rdx            ; footer
        mov [rbp - 16], rdx                 ; novo tamanho atual
        jmp _loop_merge_ahead
    
    _shrink_heap:
        mov rdx, [rbp - 8]
        add rdx, 9
        add rdx, [rbp - 16]
        add rdx, 8
        mov rax, 12
        xor rdi, rdi
        syscall
        cmp rdx, rax                        ; Se rdx == rax entao estamos no fim da heap
        jne _end_merge
        mov rax, 12
        mov rdi, [rbp - 8]
        syscall  

        _end_merge:
            add rsp, 32
            mov rax, 0

    _exit_free:
        pop rbp
        ret