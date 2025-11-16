section .note.GNU-stack progbits noalloc noexec nowrite

section .bss
heap_start: resq 1                          ; endereço do começo da heap

section .text
global setup_brk
global dismiss_brk
global get_brk
global memory_alloc
global memory_free

; pega o endereço inicial da heap
setup_brk:
    push rbp
    mov rbp, rsp

    mov rax, 12                             ; sys_brk
    xor rdi, rdi
    syscall
    mov qword [heap_start], rax

    pop rbp
    ret

; reseta o endereço da heap para o inicial
dismiss_brk:
    push rbp
    mov rbp, rsp

    mov rax, 12
    mov rdi, [heap_start]
    syscall

    pop rbp
    ret

get_brk:
    push rbp
    mov rbp, rsp

    mov rax, 12
    xor rdi, rdi
    syscall

    pop rbp
    ret

; aloca blocos na heap
; retorna o endereço da area de dados do bloco alocado
memory_alloc:
    push rbp
    mov rbp, rsp
 
    ; variaveis locais: size_block, size_worst_block, ptr_worst_block e top_heap
    sub rsp, 32
    mov [rbp-8], rdi                        ; size_block
    mov QWORD [rbp-16], 0                   ; size_worst_block
    mov QWORD [rbp-24], 0                   ; ptr_worst_block

    mov rax, 12
    xor rdi, rdi    
    syscall 
    mov [rbp-32], rax                       ; top_heap (limite do loop)

    mov rsi, [heap_start]                   ; i = começo da heap

    ; Verifica se há algum bloco livre e se ele tem o tamanho suficiente (worst fit)
    _loop:  
        cmp rsi, [rbp-32]                   ; while i < top_heap
        jge _end_loop       

        cmp BYTE [rsi], 1                   ; Se register[i]->free == 1 então pula (bloco ocupado)
        je _next_block  

        mov rdx, [rsi+1]                    ; rdx = register[i]->size_block
        cmp rdx, [rbp-8]                    ; Se register[i]->size_block < size_block então pula (bloco não cabe)
        jl _next_block  

        mov rdx, [rbp-16]                   ; rdx = size_worst_block
        cmp rdx, [rsi+1]                    ; Se size_worst_block > register[i]->size_block então pula (tamanho do bloco não é maior que o maior bloco até agora)
        jg _next_block  

        ; Atualização das variáveis locais
        mov rdx, [rsi+1]                    ; rdx = register[i]->size_block
        mov [rbp-16], rdx                   ; size_worst_block = register[i]->size_block
        mov [rbp-24], rsi                   ; ptr_worst_block = i

        ; Contiuação do loop (próximo bloco)
        _next_block:    
            mov rdx, [rsi+1]                ; rdx = register[i]->size_block
            add rsi, 9                  
            add rsi, rdx                    
            add rsi, 8                      ; i++
            jmp _loop   
            
    _end_loop:  

        mov rsi, [rbp-24]                   ; rsi = ptr_worst_block
        cmp QWORD rsi, 0                    ; Se ptr_worst_block == 0 então pula (não existe bloco livre ou com tamanho suficiente)
        je _alloc_new_block                 

        mov rdx, [rbp-16]                   ; rdx = size_worst_block
        sub rdx, [rbp-8]                    ; extra_bytes = size_block - size_worst_block

        cmp rdx, 18                         ; Se extra_bytes < 18 então pula (não tem espaço suficiente para um novo bloco)
        jl _set_block       

        ; Case 1.a: tamanho suficiente e com bytes extras suficientes para novo bloco
        mov rbx, [rbp-8]                    ; rbx = size_block
        mov QWORD [rsi+1], rbx              ; register[ptr_worst_block]->size_block = size_block (header)
        mov QWORD [rsi+9+rbx], rbx          ; register[ptr_worst_block]->size_block = size_block (footer)

        ; Cria um novo bloco 
        lea rbx, [rsi+9+rbx+8]              ; new_register
        mov BYTE [rbx], 0                   ; new_register->valid = 0
        sub rdx, 17                         ; size_block = extra_bytes - 17 (metadados)
        mov QWORD [rbx+1], rdx              ; new_register->size_block = size_block (header)
        mov QWORD [rbx+9+rdx], rdx          ; new_register->size_block = size_block (footer)
    
        ; Case 1.b: tamanho suficiente e bytes extras insuficientes para novo bloco
        ; E continuação do caso 1.a
        _set_block:
            mov BYTE [rsi], 1               ; register[ptr_worst_block]->valid = 1
            lea rax, [rsi+9]                ; retorna o endereço da area de dados do bloco
            jmp _exit_alloc

        ; Caso 2: não há bloco livre ou com tamanho suficiente
        _alloc_new_block:
            mov rax, 12                     ; sys_brk
            xor rdi, rdi                    ; zera rdi
            syscall                         ; call brk(0)

            mov rsi, rax                    ; início do novo bloco
            mov rbx, [rbp-8]                ; rbx = size_block

            ; Calculo do novo limite da heap
            add rax, 9                      ; rax += 9 (header)
            add rax, 8                      ; rax += 8 (footer)
            add rax, rbx                    ; rax += size_block
            mov rdi, rax                    ; rdi = new_top_of_heap
            mov rax, 12                     ; sys_brk
            syscall                         ; call brk(new_top_of_heap)
            
            mov BYTE [rsi], 1               ; coloca bloco como ocupado
            mov QWORD [rsi + 1], rbx        ; coloca o tamanho do bloco (header)
            mov QWORD [rsi + 9 + rbx], rbx  ; coloca o tamanho do bloco (footer)
            lea rax, [rsi+9]                ; retorna o endereço da area de dados do bloco

        _exit_alloc:
            add rsp, 32
            pop rbp
            ret

; Libera um bloco alocado
; Retorna 0 em caso de sucesso e 1 em caso de erro
memory_free:
    push rbp
    mov rbp, rsp

    cmp rdi, 0                              ; Se ptr != 0(NULL) então pula (ponteiro nulo)
    je _exit_error
    cmp BYTE [rdi-9], 0                     ; Se ptr->valid == 0 então pula (ponteiro liberado)
    je _exit_error

    ; Inicío da liberação do bloco
    sub rdi, 9                              ; pega o inicio do bloco
    mov BYTE [rdi], 0                       ; register->valid = 0 (free)

    ; Começo do merge de blocos livres adjacentes
    ; Variaveis locais: ptr_base, size_block_base, heap_start, heap_top
    sub rsp, 32
    mov [rbp - 8], rdi                      ; ptr_base
    mov rax, [rdi + 1]
    mov [rbp - 16], rax                     ; size_block_base
    mov rax, [heap_start]
    mov [rbp - 24], rax                     ; heap_start

    mov rax, 12
    xor rdi, rdi
    syscall
    mov [rbp - 32], rax                     ; heap_top
    xor rax, rax

    ; Caso 1.a: merge de blocos adjacentes para trás
    _loop_merge_behind:
        mov rdi, [rbp - 8]                  ; ptr_base
        sub rdi, 8                          ; footer de i-1
        cmp rdi, [rbp - 24]                 ; Se footer <= heap_start então pula (register[i] é o primeiro bloco)
        jle _loop_merge_ahead

        mov QWORD rdi, [rdi]                ; rdi = footer de i-1 (size_block)
        mov rdx, [rbp - 8]                  ; rdx = ptr_base
        sub rdx, 8                          ; rdx está no inicio do footer de i-1
        sub rdx, rdi                        ; rdx está no inicio da area de dados de i-1
        sub rdx, 9                          ; rdx = register[i-1]
        cmp BYTE [rdx], 1                   ; Se register[i-1]->valid == 1 então pula (bloco ocupado)
        je _loop_merge_ahead

        ; Merge de i-1 com i
        add rdi, [rbp - 16]                 ; rdi = register[i-1]->size_block + size_block_base
        add rdi, 17                         ; size_block_merged = rdi + 17 (footer(i-1) e header(i))
        mov [rdx + 1], rdi                  ; register[i-1]->size_block = rdi (header)
        mov [rdx + 9 + rdi], rdi            ; register[i-1]->size_block = rdi (footer)
        mov [rbp - 8], rdx                  ; prt_base = i-1
        mov [rbp - 16], rdi                 ; size_block_base = size_block_merged
        jmp _loop_merge_behind
    
    ; Caso 1.b: merge de blocos adjacentes para frente
    _loop_merge_ahead:
        mov rdi, [rbp - 8]                  ; ptr_base
        mov rdx, [rdi + 1]                  ; rdx = register[i]->size_block
        lea rdx, [rdi + 9 + rdx + 8]        ; rdx = i + 1
        cmp rdx, [rbp - 32]                 ; Se i + 1 >= heap_top entao pula (register[i] é o ultimo bloco)
        jge _shrink_heap

        cmp BYTE [rdx], 1                   ; Se register[i+1]->valid == 1 então pula (bloco ocupado)
        je _shrink_heap

        mov rdx, [rdx + 1]                  ; rdx = register[i+1]->size_block
        add rdx, [rbp - 16]                 ; rdx = register[i+1]->size_block + size_block_base
        add rdx, 17                         ; size_block_merged = rdx + 17 (footer(i) e header(i+1))
        mov [rdi + 1], rdx                  ; register[i]->size_block = size_block_merged (header)
        mov [rdi + 9 + rdx], rdx            ; register[i]->size_block = size_block_merged (footer)
        mov [rbp - 16], rdx                 ; size_block_base = size_block_merged
        jmp _loop_merge_ahead
    
    ; Caso 1.c: encolhimento da heap
    _shrink_heap:
        mov rdx, [rbp - 8]                  ; rdx = ptr_base
        add rdx, 9                          ; rdx está no inicio da area de dados de i
        add rdx, [rbp - 16]                 ; rdx está no começo do footer de i
        add rdx, 8                          ; rdx está no fim do bloco i
        mov rax, 12                         ; sys_brk
        xor rdi, rdi                        ; rdi = 0
        syscall                             ; call brk(0)
        cmp rdx, rax                        ; Se rdx != rax então pula (register[i] não é o ultimo bloco)
        jne _end_merge

        ; Novo topo da heap
        mov rax, 12                         ; sys_brk
        mov rdi, [rbp - 8]                  ; rdi = ptr_base
        syscall                             ; call brk(ptr_base)

        ; Liberação das variáveis locais e código de retorno de sucesso
        _end_merge:
            add rsp, 32
            mov rax, 0
            jmp _exit_free

    ; Caso 2: ponteiro nulo ou double free
    _exit_error:
        mov rax, 1
        jmp _exit_free

    ; Continuação dos casos 1.* e 2
    _exit_free:
        pop rbp
        ret