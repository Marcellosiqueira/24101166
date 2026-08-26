# Banco de Dados — IDP

Marcello Azevedo Pinheiro Siqueira
Matrícula 24101166

Entregas da disciplina. A numeração das pastas segue a numeração do repositório de
materiais do professor.

| Aula | Atividade | Entrega |
| --- | --- | --- |
| 02 | Conceito de dado e informação: sistema de aeroporto | [`atividade-01-aeroporto/`](atividade-01-aeroporto/) |
| 03 | Relacionamento de entidades utilizando arquivos | [`aula03-relacionamento-arquivos/`](aula03-relacionamento-arquivos/) |
| 04 | Simulando um SGBD sobre arquivos de texto | [`aula04-sgbd-arquivo/`](aula04-sgbd-arquivo/) |
| 05 | Modelagem de dados: sistema de aeroporto | [`aula05-modelagem-dados/`](aula05-modelagem-dados/) |
| 06 | Dicionário de dados do sistema de aeroporto | [`aula06-dicionario-dados/`](aula06-dicionario-dados/) |
| 08 | Criação do banco de dados no MySQL | [`aula08-criacao-banco/`](aula08-criacao-banco/) |

O nome `atividade-01-aeroporto` foi mantido porque o enunciado da Aula 02 pedia
explicitamente esse nome.

## Aula 02 — Conceito de dado e informação

Levantamento dos dados que um sistema de gerenciamento de aeroporto precisa armazenar e
das informações que ele deve fornecer a partir deles. Entrega em Markdown, sem código.

## Aula 03 — Relacionamento de entidades

Sistema acadêmico em Python puro, sem SGBD, relacionando `alunos.txt` e `notas.txt` para
responder consultas do tipo "qual nota o aluno X tirou na disciplina Y". O `ID_ALUNO` das
notas funciona como chave estrangeira feita à mão.

```bash
cd aula03-relacionamento-arquivos
python aula03.py
```

Os arquivos de dados são gerados na execução e estão no `.gitignore`.

## Aula 04 — Simulando um SGBD

Três operações de consulta implementadas diretamente sobre arquivo texto, usando o painel
de voos fornecido pelo professor:

- Full table scan, equivalente a `SELECT *`
- Busca por chave primária com early exit, equivalente a `WHERE ID = X`
- Filtro e projeção, equivalente a `SELECT col1, col2 WHERE condição`

Inclui um benchmark comparando o scan sequencial com um índice hash de offsets em duas
escalas, e as respostas das questões de reflexão sobre desempenho, indexação e
concorrência.

```bash
cd aula04-sgbd-arquivo
python sgbd.py    # menu interativo
python demo.py    # todas as consultas de uma vez
```

## Aula 05 — Modelagem de dados

Modelo de dados de um sistema de aeroporto a partir das entidades PASSAGEIRO, VOO e
AERONAVE: atributos, chaves, cardinalidades, resolução do relacionamento N:N por tabela
associativa, modelo lógico e diagrama.

Entregue em PDF e em Markdown. O DDL do apêndice foi executado e testado contra as
violações que o documento afirma que o banco recusa.

## Aula 06 — Dicionário de dados

Documentação técnica do banco `aeroporto` sobre o modelo de dicionário fornecido
pelo professor: ficha de cada uma das quatro tabelas com tipo, tamanho,
obrigatoriedade, chave, default, domínio e exemplo de cada campo, mais os
relacionamentos, 9 regras de negócio, os domínios controlados e os 11 índices.

Entregue em `.docx`, formato do modelo original.

## Aula 08 — Criação do banco de dados

Implementação em MySQL do modelo da Aula 05: banco `aeroporto` com as tabelas
`aeronave`, `passageiro`, `voo` e a associativa `passagem`, mais os dados de
exemplo e as consultas.

Inclui um script de verificação que roda 10 comandos que devem ser recusados pelo
banco e 3 que devem passar, provando que as regras de negócio do modelo estão nas
constraints e não apenas na aplicação.

```bash
mysql -u root -p < aeroporto.sql
mysql -u root -p --force aeroporto < testes_constraints.sql
```

## Ambiente

Python 3.12, sem dependências externas.
MySQL 8.x para a Aula 08, com o script testado também em MariaDB 10.11.
