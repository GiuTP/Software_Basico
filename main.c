#include <stdio.h>
#include <unistd.h>

// Função auxiliar
void *get_brk();

// API de funções de alocação dinâmica de memória
void setup_brk();
void dismiss_brk();
void *memory_alloc(unsigned long int);
int memory_free(void *pointer);

int main(){

    setup_brk();

    // The values described in the comments should be checked using GDB
    
    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 1: frist allocation
     * p1 = 0x405009
    */
    void *p1 = memory_alloc(100);

    /* EXECUTED WITHOUT ERRORS USING GDB */
    /*  Test 2: next allocation after first allocation
     * p2 = 0x40507E
    */
    void *p2 = memory_alloc(20);

    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 3: allocation with worst fit and split
     * s = 0x4050A3 && return 0
     * t1 = 0x4050E6
     * m = 0x4050F8 && return 0
     * t2 = 0x405203
     * l = 0x405215 && return 0
     * p3 = 0x405215
     * t3 = 0x4052BC
    */
    void *s = memory_alloc(50); /* RIGHT */
    void *t1 = memory_alloc(1); /* RIGHT */
    void *l = memory_alloc(250);/* RIGHT */
    void *t2 = memory_alloc(1); /* RIGHT */
    void *m = memory_alloc(150);/* RIGHT */
    void *t3 = memory_alloc(1); /* RIGHT */
    if ((memory_free(s) != 0) || (memory_free(l) != 0) || (memory_free(m) != 0)){
        printf("ERRO TESTE 3\n");
        return -1;
    }
    s = NULL;
    l = NULL;
    m = NULL;
    void *split_check = memory_alloc(50);/* RIGHT */

    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 4: checking new record after split 
     * p4 = 0x40513B
    */
    void *p4 = memory_alloc(180);

    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 5: allocation with worst fit and no splitting (there's just one free record that fits)
     * p5 = 0x405215
    */
    void *p5 = memory_alloc(150);


    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 6: merge ahead
     * p6 = 0x4052CE
     * p7 = 0x40531B 
     * m1 = 0x405215
    */
    void *p6 = memory_alloc(60); /* RIGHT */
    void *p7 = memory_alloc(70); /* RIGHT */
    if ((memory_free(p5) != 0) || (memory_free(t3) != 0)){ /* RIGHT */
        printf("ERRO TESTE 6\n");
        return -1;
    }
    p5 = NULL;
    t3 = NULL;
    void *m_ahead = memory_alloc(168);/* RIGHT */

    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 7: merge behind
     * m_behind = 0x405203
    */
    if ((memory_free(t2) != 0) || (memory_free(m_ahead) != 0))/* RIGHT */
    {
        printf("ERRO TESTE 7\n");
        return -1;
    }
    m_ahead = NULL;
    t2 = NULL;
    void *m_behind = memory_alloc(186);

    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 8: merge behind and ahead
     * m_both = 0x4050A3
    */
    if ((memory_free(split_check) != 0) || (memory_free(t1) != 0))/* RIGHT */
    {
        printf("ERRO TESTE 8\n");
        return -1;
    }
    void *m_both = memory_alloc(135);

    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 9: shrink heap (free at last record) */
    void *top_heap_before_free = get_brk();
    if ((memory_free(p7) != 0))
    {
        printf("ERRO TESTE 9\n");
        return -1;
    }
    /* Pointer p7 not nullified (p7 = NULL) to test double free afterwards */
    void *top_heap_after_free = get_brk();
    if ((top_heap_after_free >= top_heap_before_free))
        return -1;
    if (top_heap_after_free != ((char*)p7 - 9))
        return -1;
    
    /* EXECUTED WITHOUT ERRORS USING GDB */
    /* Test 10: double free */
    if ((memory_free(p7) != 1))
    {
        printf("ERRO TESTE 10a\n");
        return -1;
    }
    if ((memory_free(p1) != 0)){
        printf("ERRO TESTE 10b\n");    
        return -1;
    }
    if ((memory_free(p1) != 1)){
        printf("ERRO TESTE 10c\n");
        return -1;
    }
    p1 = NULL;

    // /* Free in remaining pointers */
    if ((memory_free(p2) != 0) || (memory_free(p4) != 0) || (memory_free(p6) != 0) || (memory_free(m_behind) != 0) || (memory_free(m_both) != 0))
        return -1;

    void *final_brk = get_brk();
    final_brk = NULL;
    if (memory_free(final_brk) != 1)
        return -1;
    
    dismiss_brk();
    
    return 0;
}