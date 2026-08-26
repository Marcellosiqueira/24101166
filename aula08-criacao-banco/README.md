# Aula 08 — Criação do banco de dados no MySQL

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Implementação em MySQL do modelo lógico desenhado na Aula 05: as entidades
PASSAGEIRO, VOO e AERONAVE, mais a tabela associativa PASSAGEM que resolve o
relacionamento N:N.

## Arquivos

| Arquivo | Conteúdo |
| --- | --- |
| `aeroporto.sql` | Script completo: cria o banco, as tabelas, insere os dados e executa as consultas |
| `testes_constraints.sql` | Verificação das regras de negócio: 10 comandos que devem falhar e 3 que devem funcionar |

## O que a atividade pedia

| Item | Onde está |
| --- | --- |
| Criar um banco chamado `aeroporto` | seção 1 do `aeroporto.sql` |
| Criar as tabelas já planejadas | seção 2 |
| Inserir pelo menos 5 tuplas em cada entidade | seção 4: 6 aeronaves, 9 passageiros, 8 voos, 12 passagens |
| Executar `SELECT` para visualizar os dados | seção 5 |
| Reproduzir no Workbench e no Laragon | instruções abaixo |

## Como executar

### MySQL Workbench

1. Abrir o Workbench e conectar em `root@127.0.0.1:3306`
2. `File > Open SQL Script`, selecionar `aeroporto.sql`
3. Executar o script inteiro com o ícone de raio duplo, ou `Ctrl+Shift+Enter`
4. Atualizar o painel Schemas para ver o banco `aeroporto` com as quatro tabelas
5. Os resultados dos `SELECT` aparecem em abas separadas na parte de baixo

O script começa com `DROP DATABASE IF EXISTS aeroporto`, então pode ser rodado
quantas vezes for preciso sem dar erro de objeto duplicado. O lado ruim é óbvio:
ele apaga o banco inteiro a cada execução. É o comportamento certo para uma
atividade de aula e o comportamento errado em qualquer coisa com dado real.

### Laragon

1. Abrir o Laragon e clicar em `Start All`
2. Conferir que o MySQL subiu na porta 3306
3. Clicar em `Database`, o que abre o HeidiSQL já conectado
4. `Arquivo > Executar arquivo SQL`, selecionar `aeroporto.sql`
5. Depois de rodar, `SHOW TABLES;` numa nova aba de consulta lista as quatro tabelas

### Linha de comando

```bash
mysql -u root -p < aeroporto.sql
mysql -u root -p --force aeroporto < testes_constraints.sql
```

A flag `--force` no segundo comando faz o cliente continuar após cada erro. Sem
ela o script para no primeiro, e o objetivo justamente é ver os dez erros.

## Decisões de implementação

**`utf8mb4` e não `utf8`.** No MySQL, `utf8` é apelido para `utf8mb3`, que usa no
máximo 3 bytes por caractere e não cobre emoji nem parte dos acentos. A collation
escolhida foi `utf8mb4_unicode_ci`, que existe tanto no MySQL quanto no MariaDB.
A `utf8mb4_0900_ai_ci`, padrão do MySQL 8, não existe no MariaDB e quebraria a
portabilidade do script.

**`ENGINE = InnoDB` explícito.** É o padrão desde o MySQL 5.5, mas deixar escrito
evita surpresa em configuração antiga. MyISAM aceita a sintaxe de chave
estrangeira e simplesmente ignora, o que é pior que dar erro: o banco aceitaria
registros órfãos em silêncio.

**`cpf` aceita `NULL`.** Passageiro estrangeiro não tem CPF, e chave primária não
aceita nulo. Foi por isso que a Aula 05 escolheu a chave substituta
`id_passageiro`. A constraint `UNIQUE` continua valendo porque, no padrão SQL,
vários `NULL` não conflitam entre si: `NULL` não é igual a `NULL`. O script tem
dois passageiros sem CPF exercitando exatamente isso.

**`portao` é `VARCHAR` e não `INT`.** Tem zero à esquerda (`08`, `01`) e é
identificador, não quantidade. Ninguém soma portões.

**`UNIQUE (numero_voo, data_hora_partida)`.** O voo 305 acontece todo dia, então
`numero_voo` sozinho não é chave. Os dados inseridos incluem o voo 305 em dois
dias diferentes, mostrando que a constraint permite a repetição do número e
bloqueia a do par.

**`ON DELETE RESTRICT`.** Apagar uma aeronave que ainda tem voos, ou um voo que
ainda tem passagens, é recusado. `CASCADE` apagaria os filhos junto, o que num
sistema de aeroporto significaria sumir com as passagens vendidas sem nenhum
aviso.

## Verificação das constraints

O `testes_constraints.sql` roda 10 comandos que devem falhar e 3 que devem
funcionar. Resultado da execução:

| Teste | Regra violada | Erro |
| --- | --- | --- |
| Mesmo passageiro em dois assentos no mesmo voo | `uq_passagem_passageiro_voo` | 1062 |
| Dois passageiros no mesmo assento | `uq_passagem_voo_assento` | 1062 |
| Passagem para voo inexistente | `fk_passagem_voo` | 1452 |
| Voo com aeronave inexistente | `fk_voo_aeronave` | 1452 |
| Status fora do domínio | `ck_voo_status` | 4025 |
| Origem igual ao destino | `ck_voo_rota` | 4025 |
| Voo repetido no mesmo horário | `uq_voo_numero_partida` | 1062 |
| CPF duplicado | `uq_passageiro_cpf` | 1062 |
| Apagar aeronave com voos | `fk_voo_aeronave` | 1451 |
| Aeronave com capacidade zero | `ck_aeronave_capacidade` | 4025 |

E as três contraprovas passam: segundo passageiro sem CPF, mesmo passageiro em
outro voo, e mesmo número de assento em voo diferente.

O ponto dessa verificação é que o desafio da Aula 05, impedir que um passageiro
ocupe dois assentos no mesmo voo, deixou de ser uma proposta no papel e virou uma
regra que o banco aplica. Validação em código pode ser esquecida numa rota nova,
contornada por script de correção ou perdida numa condição de corrida entre dois
check-ins simultâneos. A constraint não tem esse problema, porque é avaliada
dentro da transação.

## Consultas incluídas

Além dos quatro `SELECT *` pedidos, o script traz cinco consultas que exercitam o
modelo:

- Painel de voos com `JOIN` entre VOO e AERONAVE
- Lista de embarque de um voo específico, atravessando a tabela associativa com
  dois `JOIN`
- Ocupação por voo comparando passagens vendidas com a capacidade da aeronave
- Passageiros com mais de um voo, usando `GROUP BY` e `HAVING`
- Próximos voos a partir de um horário

A consulta de ocupação usa `LEFT JOIN` de propósito. Com `JOIN` simples, um voo
sem nenhuma passagem vendida sumiria do resultado, e é justamente esse voo que
interessa num relatório de ocupação. O voo 305 do dia 02 aparece com zero por
esse motivo.

## Ambiente

Script testado em MariaDB 10.11. Compatível com MySQL 8.x, versão que o Laragon
instala.

Uma ressalva sobre as constraints `CHECK`: MySQL só passou a aplicá-las na versão
8.0.16. Em versões anteriores a sintaxe é aceita e silenciosamente ignorada, o
que faria os testes 5, 6 e 10 passarem quando deveriam falhar. Se algum deles não
der erro, o motivo é a versão do servidor, não o script.
