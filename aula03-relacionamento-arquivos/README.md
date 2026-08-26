# Aula 03 - Relacionamento de entidades utilizando arquivos

Atividade da disciplina de Banco de Dados. O objetivo é simular o relacionamento
entre duas entidades (Aluno e Nota) usando **apenas arquivos de texto**, sem
nenhum SGBD (sem SQLite, MySQL, PostgreSQL etc.). Os dados ficam gravados em
disco e continuam disponíveis entre uma execução e outra.

## Estrutura dos dados

O sistema usa dois arquivos, criados automaticamente na primeira gravação:

**alunos.txt** — uma linha por aluno:

```
ID;NOME;TELEFONE;EMAIL
1;Ana Souza;61999990000;ana@email.com
```

**notas.txt** — uma linha por nota:

```
ID_ALUNO;DISCIPLINA;NOTA
1;Banco de Dados;9.5
```

O campo `ID_ALUNO` de `notas.txt` referencia o campo `ID` de `alunos.txt`,
funcionando como uma **chave estrangeira** feita "na mão".

## Como executar

```bash
python aula03.py
```

O programa abre um menu em loop com as opções:

| Opção | Funcionalidade |
|-------|----------------|
| 1 | Cadastrar aluno (não permite ID duplicado) |
| 2 | Listar alunos |
| 3 | Buscar aluno por nome (sem diferenciar maiúsculas de minúsculas) |
| 4 | Cadastrar nota (só grava se o aluno existir e se a nota for numérica) |
| 5 | Consultar nota de um aluno em uma disciplina |
| 6 | Listar todas as notas de um aluno |
| 7 | Calcular a média de um aluno (2 casas decimais) |
| 8 | Buscar alunos por disciplina |
| 9 | Editar uma nota |
| 10 | Excluir uma nota (com confirmação) |
| 11 | Buscar alunos com nota acima de um valor |
| 0 | Sair |

Os arquivos `alunos.txt` e `notas.txt` não são versionados (estão no
`.gitignore`), porque são dados de execução e não código.

## Reflexão

**Como o programa identifica a qual aluno uma nota pertence?**
Pelo `ID_ALUNO` gravado na linha da nota. Esse número é o mesmo `ID` que
identifica o aluno de forma única em `alunos.txt`. Para consultar uma nota, o
programa primeiro localiza o aluno pelo nome, pega o `ID` dele e só então varre
`notas.txt` procurando as linhas cujo primeiro campo seja igual a esse `ID`.

**Por que usar um identificador único em vez do nome?**
Porque nomes se repetem e mudam. Dois alunos podem se chamar "Ana Souza"
(homônimos), e nesse caso não haveria como saber de quem é a nota. Além disso,
um nome pode ser corrigido ou alterado, e todas as notas ligadas a ele ficariam
órfãs. O ID é estável: nunca muda e nunca se repete, então a ligação entre os
arquivos continua válida.

**Como garantir que uma nota pertença a um aluno existente?**
Validando antes de gravar. Na opção "Cadastrar nota", o programa procura o ID
informado em `alunos.txt`; se não encontrar, a nota simplesmente não é escrita
no arquivo. Isso evita notas apontando para alunos que não existem.

**Quais dificuldades surgem quando os dados estão em arquivos separados?**
Toda a integridade referencial fica por conta do programa: nada impede que
alguém edite `alunos.txt` no bloco de notas e apague um aluno que ainda tem
notas, deixando registros órfãos. Também não existe índice — para achar um
aluno é preciso ler o arquivo linha por linha, o que fica lento conforme os
dados crescem. Não há tipos de dados (tudo é texto), nem controle de acesso
simultâneo, e o caractere `;` usado como separador não pode aparecer dentro de
um campo. Um SGBD resolve tudo isso com chaves primárias e estrangeiras,
índices, tipagem e transações.
