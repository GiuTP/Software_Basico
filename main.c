#include <stdio.h>
#include <assert.h>
#include <unistd.h>

void setup_brk();
void dismiss_brk();
void *memory_alloc(unsigned long int);
int memory_free(void *pointer);

int main(){

    setup_brk();

    // Valores descritos nos comentarios devem ser consultados pelo gdb
    
    /* Test 1: frist allocation
     * p1 = 0x40509
     * [[O 50]]
    */
    void *p1 = memory_alloc(100);

    /*  Test 2: next allocation after first allocation
     * p2 = 0x4057E 
     * [[O 50][O 20]]
    */
    void *p2 = memory_alloc(20);

    /* Test 3: allocation with worst fit and split
     * s = 0x40587 && return 0
     * t1 = 0x405D0
     * m = 0x405E2 && return 0
     * t2 = 0x406ED
     * l = 0x406FF && return 0
     * p3 = 0x405E2
     * [[O 50][O 20][O 50][O 1][O 250][O 1][O 150]]
    */
    void *s = memory_alloc(50);
    void *t1 = memory_alloc(1);
    void *l = memory_alloc(250);
    void *t2 = memory_alloc(1);
    void *m = memory_alloc(150);
    if ((memory_free(s) != 0) || (memory_free(l) != 0) || (memory_free(m) != 0))
        return -1;
    void *p3 = memory_alloc(50);

    /* Test 4: checking new record after split 
     * p4 = 0x4061C 
     * [[O 50][O 20][L 50][O 1][O 50][L 183][O 1][O 150]]
    */
    void *p4 = memory_alloc(150);

    /* Test 5: allocation with worst fit and no split
     * p5 = 0x406FF 
     * [[O 50][O 20][L 50][O 1][O 50][O 150][L 16][O 1][O 150]]
    */
    void *p5 = memory_alloc(150);

    /* Test 6: merge ahead
     * p6 = 0x407EA
     * p7 = 0x407F3 
     * m1 = 0x406FF
     * [[O 50][O 20][L 50][O 1][O 50][O 150][L 16][O 1][O 210][O 70]]
    */
    void *p6 = memory_alloc(60);
    void *p7 = memory_alloc(70);
    if ((memory_free(p5) != 0) || (memory_free(p6) != 0))
        return -1;
    void *m1 = memory_alloc(210);

    /* Test 7: merge behind
     * p8 = 0x406ED
     * [[O 50][O 20][L 50][O 1][O 50][O 150][L 16][O 211][O 70]]
    */
    if ((memory_free(m1) != 0) || (memory_free(t2) != 0))
        return -1;
    void *p8 = memory_alloc(211);

    /* Test 8: merge behind and ahead
     * p9 = 0x40587
     * [[O 50][O 20][O 101][O 150][L 16][O 211][O 70]]
    */
    if ((memory_free(p3) != 0) || (memory_free(t1) != 0))
        return -1;
    void *p9 = memory_alloc(101);

    /* Test 9: shrink heap (free at last record)
     * [[O 50][O 20][O 101][O 150][L 16][O 211]]
     */
    void *top_heap_before_free = sbrk(0);
    if ((memory_free(p7) != 0))
        return -1;
    void *top_heap_after_free = sbrk(0);
    if ((top_heap_after_free >= top_heap_before_free))
        return -1;
    if (top_heap_after_free != ((char*)p7 - 9))
        return -1;
    
    /* Test 10: double free 
     * [[L 50][O 20][O 101][O 150][L 16][O 211]]
     */
    if ((memory_free(p7) != 1))
        return -1;
    if ((memory_free(p1) != 0))    
        return -1;
    if ((memory_free(p1) != 1))
        return -1;

    /* Free in remaining pointers */
    if ((memory_free(p2) != 0) || (memory_free(p4) != 0) || (memory_free(p9) != 0))
        return -1;
    
    dismiss_brk();
    
    return 0;
}