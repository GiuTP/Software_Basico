#include <stdio.h>
#include <assert.h>
#include <unistd.h>

void setup_brk();
void dismiss_brk();
void *memory_alloc(unsigned long int);
void memory_free(void *pointer);

int main(){

    setup_brk();

    printf("Iniciando testes\n");

    printf("Fim dos testes\n");

    dismiss_brk();
    
    return 0;
}