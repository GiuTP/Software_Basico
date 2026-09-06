<a id="readme-top"></a>

[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![LinkedIn][linkedin-shield]][linkedin-url]

<br />
<div align="center">
  <h3 align="center">🧠 Heap Manager em Assembly AMD64</h3>

  <p align="center">
    Implementação de um gerenciador de memória heap em Assembly AMD64 — trabalho da disciplina Software Básico (CI1064) na UFPR.
    <br />
    <a href="https://github.com/giutp/software-basico/issues/new?labels=bug">Reportar Bug</a>
    &middot;
    <a href="https://github.com/giutp/software-basico/issues/new?labels=enhancement">Sugerir Melhoria</a>
  </p>
</div>

---

<!-- SUMÁRIO -->
<details>
  <summary>Sumário</summary>
  <ol>
    <li><a href="#-sobre-o-projeto">Sobre o Projeto</a>
      <ul>
        <li><a href="#-construído-com">Construído com</a></li>
      </ul>
    </li>
    <li><a href="#-fundamentação--arquitetura">Fundamentação / Arquitetura</a></li>
    <li><a href="#-api-e-componentes">API e Componentes</a></li>
    <li><a href="#-dinâmica-e-fluxo-de-execução">Dinâmica e Fluxo de Execução</a></li>
    <li><a href="#-estrutura-de-um-bloco-de-memória">Estrutura de um Bloco de Memória</a></li>
    <li><a href="#-estrutura-do-projeto">Estrutura do Projeto</a></li>
    <li>
      <a href="#-instalação">Instalação</a>
      <ul>
        <li><a href="#-pré-requisitos">Pré-requisitos</a></li>
        <li><a href="#-compilação">Compilação</a></li>
        <li><a href="#-comandos-úteis">Comandos Úteis</a></li>
      </ul>
    </li>
    <li><a href="#-dificuldades-e-aprendizados">Dificuldades e Aprendizados</a></li>
    <li><a href="#-licença">Licença</a></li>
    <li><a href="#-contato">Contato</a></li>
    <li><a href="#-agradecimentos">Agradecimentos</a></li>
  </ol>
</details>

---

## 📖 Sobre o Projeto

**Heap Manager** é uma implementação completa de um gerenciador de alocação dinâmica de memória heap desenvolvida inteiramente em **Assembly AMD64 (NASM)**, para a disciplina **Software Básico (CI1064)** da **Universidade Federal do Paraná (UFPR)**.

O projeto expõe uma API compatível com chamada de código C externo, simulando o comportamento de funções como `malloc` e `free`. O gerenciador manipula diretamente o *program break* via syscall `brk`, mantendo uma lista linear de blocos com metadados de controle (cabeçalho + rodapé) embutidos na própria heap. A estratégia de busca adotada é o **worst-fit**: ao alocar, o maior bloco livre compatível é escolhido, minimizando a geração de fragmentos inúteis em alocações futuras. Blocos liberados são **coalescidos** automaticamente com vizinhos livres adjacentes, e a heap é **retraída** via `brk` quando o último bloco é liberado.

A validação foi realizada por meio de um programa em C (`main.c`) com 10 testes distintos, depurado com **GDB** para verificar endereços e estados de memória.

Trabalho realizado em dupla.

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

### 🛠 Construído com

* [![Assembly][ASM-badge]][ASM-url]
* [![C][C-badge]][C-url]
* [![Linux][Linux-badge]][Linux-url]

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## ⏱ Arquitetura

O gerenciador opera diretamente sobre a heap do processo via syscall `brk` (número 12 no Linux AMD64). Cada bloco alocado é precedido por um **registro de controle de 9 bytes** (1 byte de uso + 8 bytes de tamanho) e sucedido por um **rodapé de 8 bytes** (tamanho repetido), formando um layout de bloco com fronteiras bidirecionais — o que possibilita a coalescência em ambas as direções (para trás e para frente) durante a liberação.

```
+----------------------------------------------------------+
|              Layout da Heap (AMD64)                      |
|                                                          |
|  [ USO (1B) | TAMANHO (8B) | DADOS (N bytes) | TAM (8B)]|
|  ^-- Cabeçalho (header) ----^                ^-- Footer  |
|                                                          |
|  Estrutura encadeada linearmente na heap.                |
|  Traversal: ptr_atual += 9 + tamanho + 8                 |
+----------------------------------------------------------+
```

A estratégia de alocação é **worst-fit**: percorre-se toda a lista de blocos livres e escolhe-se o de maior tamanho que satisfaz a requisição. Se o bloco escolhido tem bytes extras ≥ 18 (17 de metadados + 1 de dado), ele é **dividido (split)** em dois blocos menores.

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 🔧 API

| Função | Assinatura | Descrição |
|--------|------------|-----------|
| **`setup_brk`** | `void setup_brk()` | Obtém e armazena o endereço inicial da heap via `brk(0)`. Deve ser chamada uma vez antes de qualquer alocação. |
| **`dismiss_brk`** | `void dismiss_brk()` | Restaura o *program break* ao valor salvo por `setup_brk`, devolvendo toda a heap ao SO. |
| **`get_brk`** | `void* get_brk()` | Auxiliar: retorna o topo atual da heap via `brk(0)`. Usado nos testes para verificação de estado. |
| **`memory_alloc`** | `void* memory_alloc(unsigned long int bytes)` | Aloca um bloco de `bytes` bytes. Usa worst-fit com split automático. Retorna ponteiro para a área de dados. |
| **`memory_free`** | `int memory_free(void *ptr)` | Libera o bloco apontado por `ptr`. Realiza coalescência bidirecional e retração da heap. Retorna `0` em sucesso e `1` em erro (ponteiro nulo ou double-free). |

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 🔄 Dinâmica e Fluxo de Execução

| Etapa | Comportamento |
|-------|----------------------------------|
| `setup_brk()` | Registra o endereço inicial da heap em variável `.bss`. A partir daqui, toda a heap é controlada pelo gerenciador. |
| `memory_alloc(N)` — **worst-fit** | Percorre todos os blocos da heap. Seleciona o maior bloco livre com tamanho ≥ N. Se nenhum é encontrado, expande a heap via `brk`. |
| `memory_alloc(N)` — **split** | Se o bloco escolhido tem bytes extras ≥ 18, divide-o: o primeiro recebe N bytes (marcado como ocupado); o restante vira um novo bloco livre com header e footer próprios. |
| `memory_alloc(N)` — **novo bloco** | Calcula o novo topo (`brk atual + 9 + N + 8`), chama `brk(novo_topo)` e inicializa o registro do bloco. |
| `memory_free(ptr)` | Valida o ponteiro (não-nulo e ocupado). Marca como livre. Inicia coalescência. |
| `memory_free` — **merge para trás** | Lê o rodapé do bloco anterior; se estiver livre, une os dois blocos ajustando header e footer do bloco resultante. Repete até encontrar bloco ocupado ou início da heap. |
| `memory_free` — **merge para frente** | Verifica o header do bloco seguinte; se estiver livre, une-os. Repete até encontrar bloco ocupado ou fim da heap. |
| `memory_free` — **retração da heap** | Após coalescência, se o bloco resultante for o último, chama `brk(ptr_base)` para devolver a memória ao SO. |
| `dismiss_brk()` | Restaura o *program break* ao valor inicial, limpando completamente a heap gerenciada. |

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 🧩 Estrutura de um Bloco de Memória

O projeto não usa TADs em C, mas define uma **estrutura de metadados inline na heap** com boundary tags bidirecionais:

* **Cabeçalho / Header (`9 bytes`):** 1 byte de flag de uso (`0` = livre, `1` = ocupado) + 8 bytes com o tamanho do bloco de dados.
* **Área de dados (`N bytes`):** região retornada ao usuário via `memory_alloc`. O ponteiro devolvido aponta para o byte imediatamente após o cabeçalho.
* **Rodapé / Footer (`8 bytes`):** réplica do tamanho do bloco. Permite encontrar o header do bloco anterior em O(1), viabilizando o **merge para trás** durante a liberação.

```
Endereço base do bloco:
  [0]          → flag de uso (1 byte)
  [1..8]       → tamanho N (8 bytes, quadword)
  [9..9+N-1]   → área de dados (N bytes)  ← ponteiro retornado ao usuário
  [9+N..9+N+7] → rodapé: tamanho N repetido (8 bytes)
```

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 📁 Estrutura do Projeto

```
software-basico/
├── heap.s              implementação da API de gerenciamento de heap (Assembly AMD64 / NASM)
├── main.c              programa de testes em C (10 cenários, validado via GDB)
├── makefile            automação de compilação e limpeza
└── README.md
```

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 🚀 Instalação

### 📦 Pré-requisitos

É necessário ter o assembler **NASM**, o compilador **GCC** e o **GNU Make**. No Ubuntu/Debian:

```sh
sudo apt update
sudo apt install nasm gcc make gdb -y
```

### 🔧 Compilação

1. Clone o repositório:
   ```sh
   git clone https://github.com/giutp/software-basico.git
   cd software-basico
   ```

2. Compile o projeto:
   ```sh
   make
   ```
   Isso monta `heap.s` com NASM, compila `main.c` com GCC e linka ambos em um único executável.

3. Execute os testes:
   ```sh
   make run
   ```

### ⚙ Comandos Úteis

| Comando | Descrição |
|---------|-----------|
| `make` | Monta `heap.s`, compila `main.c` e linka o executável |
| `make clean` | Remove os arquivos-objeto e o executável gerado |

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 📚 Dificuldades e Aprendizados

Ao longo do desenvolvimento, os principais desafios enfrentados foram:

- **Comunicação entre Assembly puro e C** — Entender a ABI (Application Binary Interface) do System V AMD64 foi fundamental: registradores de argumento (`rdi`, `rsi`, `rdx`...), preservação de registradores caller/callee-saved, alinhamento de pilha a 16 bytes antes de `call`, e como exportar símbolos globais com `global` no NASM para que o linker os resolva ao unir com o objeto gerado pelo GCC.

- **Estrutura e convenções de um código Assembly** — Diferente de linguagens de alto nível, Assembly exige controle manual de toda a pilha (prólogo/epílogo com `push rbp` / `pop rbp`), das variáveis locais (reservadas com `sub rsp, N`) e dos registradores. Aprender a usar labels locais (`_loop`, `_end_loop`) para estruturar laços e desvios condicionais sem perder legibilidade foi um aprendizado essencial.

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 📄 Licença

O código-fonte deste projeto está distribuído sob a licença **MIT**. Consulte o arquivo `LICENSE` para mais informações.

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 📬 Contato

giutp: [github.com/giutp](https://github.com/giutp)

E-mail — giulianotpt@gmail.com

Link do projeto: [https://github.com/giutp/software-basico](https://github.com/giutp/software-basico)

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

## 🙏 Agradecimentos

* [Prof. Jorge Pires Correia (DINF/UFPR)](https://secret.pages.c3sl.ufpr.br/author/jorge-pires-correia/) — pela disciplina e pelo enunciado do trabalho
* [Best-README-Template](https://github.com/othneildrew/Best-README-Template) — template base deste README

<p align="right">(<a href="#readme-top">voltar ao topo</a>)</p>

---

<!-- MARKDOWN LINKS & IMAGES -->
[stars-shield]: https://img.shields.io/github/stars/giutp/software-basico.svg?style=for-the-badge
[stars-url]: https://github.com/giutp/software-basico/stargazers
[issues-shield]: https://img.shields.io/github/issues/giutp/software-basico.svg?style=for-the-badge
[issues-url]: https://github.com/giutp/software-basico/issues
[license-shield]: https://img.shields.io/github/license/giutp/software-basico.svg?style=for-the-badge
[license-url]: https://github.com/giutp/software-basico/blob/main/LICENSE
[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555
[linkedin-url]: https://www.linkedin.com/in/<SEU_LINKEDIN>/
[ASM-badge]: https://img.shields.io/badge/Assembly-AMD64-6E4C13?style=for-the-badge&logo=assemblyscript&logoColor=white
[ASM-url]: https://www.nasm.us/
[C-badge]: https://img.shields.io/badge/C-00599C?style=for-the-badge&logo=c&logoColor=white
[C-url]: https://en.wikipedia.org/wiki/C_(programming_language)
[Linux-badge]: https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black
[Linux-url]: https://www.kernel.org/
