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
| 09 | Normalização do banco de dados | [`aula09-normalizacao/`](aula09-normalizacao/) |
| 10 | Restrições de integridade | [`aula10-integridade/`](aula10-integridade/) |

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

## Aula 09 — Normalização do banco de dados

Análise de normalização do banco `aeroporto` partindo do SQL da Aula 08, percorrendo da
1FN à 5FN. Duas violações com dependência funcional identificada e anomalia concreta:

- **2FN em `voo`** — `numero_voo` determina origem e destino, e é apenas parte da chave
  candidata `(numero_voo, data_hora_partida)`. Extraída a tabela `rota`.
- **3FN em `aeronave`** — `modelo` determina `fabricante`, dependência transitiva.
  Extraída a tabela `modelo_aeronave`.

As outras três formas normais são verificadas e mantidas sem alteração, com justificativa,
como o enunciado pede. Quatro dependências plausíveis foram examinadas e descartadas por
análise do domínio, entre elas a capacidade de assentos, que permanece em `aeronave`
porque a mesma aeronave pode ter configurações de cabine diferentes.

Quatro tabelas passam a seis. O SQL normalizado foi executado em MySQL 8.0.46 e as cinco
consultas da Aula 08 retornam resultado idêntico nos dois esquemas.

```bash
mysql -u root -p < sql_aula_8.sql        # banco da Aula 08, preservado
mysql -u root -p < sql_normalizado.sql   # banco normalizado
```

## Aula 10 — Restrições de integridade

Regras de integridade do banco `aeroporto` sobre o esquema normalizado da Aula 09,
organizadas nas sete categorias do enunciado: entidade, referencial, domínio, chave,
unicidade, obrigatoriedade e regras de negócio. Cada restrição tem justificativa do
problema que evita, incluindo o que `ON DELETE CASCADE` destruiria em cada uma das cinco
chaves estrangeiras.

Quatro regras novas em relação à Aula 09: chegada prevista posterior à partida, formato
IATA em origem e destino, e o limite de passagens vendidas pela capacidade da aeronave —
esta última por trigger, por ser a única forma de expressá-la no SGBD, já que o `CHECK` do
MySQL não aceita subconsulta nem agregação.

Inclui uma seção sobre as regras **deliberadamente não implementadas**, com o motivo de
cada uma: `UNIQUE` em e-mail bloquearia família que compartilha contato, `NOT NULL` em
portão impediria cadastrar voo programado, e a detecção de voos simultâneos do mesmo
passageiro bloquearia conexão legítima.

41 testes executados em MySQL 8.0.46: 31 comandos que devem ser recusados, com o código de
erro conferido na saída do servidor, e 10 contraprovas mostrando que nenhuma restrição
bloqueia operação válida.

```bash
mysql -u root -p < sql_integridade.sql
```

## Ambiente

Python 3.12, sem dependências externas.
MySQL 8.x para as Aulas 08, 09 e 10, com o script da Aula 08 testado também em
MariaDB 10.11.
