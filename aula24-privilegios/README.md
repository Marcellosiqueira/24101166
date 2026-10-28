# Aula 24: Privilégios em banco de dados

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Continuação do sistema de voos da Aula 23. A aplicação passa a conectar com a conta
`app_aeroporto`, com privilégios só nas tabelas e operações que usa. A entrega pedida
(`SHOW GRANTS`, tabela da Parte 3, respostas da Parte 4 e erros do desafio) está em
[`RELATORIO.md`](RELATORIO.md).

## O que mudou em relação à Aula 23

| Arquivo | Mudança |
| --- | --- |
| `banco/usuario_app.sql` | cria `app_aeroporto`, com `GRANT` tabela por tabela e sem `DELETE` |
| `banco/desafio_relatorios.sql` | novo: conta `relatorios`, privilégio por coluna e view |
| `.env.example` | `DB_USER=app_aeroporto` |

O código PHP não mudou: a conexão já lia usuário e senha do `.env`.

## Como executar no Laragon

1. Se o banco ainda não tem a Aula 23: rodar `aula10-integridade/sql_integridade.sql`,
   opcionalmente `aula15-triggers/triggers.sql`, `banco/migration_soft_delete.sql` e
   `banco/migration_sql_injection.sql` (cópias das Aulas 22 e 23).
2. Rodar `banco/usuario_app.sql` como root. Ele termina mostrando o `SHOW GRANTS`.
3. Copiar `.env.example` para `.env` e conferir a senha.
4. Copiar a pasta para `C:\laragon\www\` e abrir
   `http://localhost/aula24-privilegios/public/`.
5. Desafio: `banco/desafio_relatorios.sql` como root, testando com a conta
   `relatorios` entre os passos.

A conta `aeroporto_app` das Aulas 21 a 23 continua existindo para as pastas dessas
aulas funcionarem. Para removê-la: `DROP USER 'aeroporto_app'@'localhost';`.

## Teste

MySQL 8.0.46 e PHP 8.3, aplicação conectada como `app_aeroporto`:

| Teste | Resultado |
| --- | --- |
| Listar, criar, editar e excluir (soft delete) pela aplicação | funcionam |
| `DELETE` e `DROP` no cliente MySQL | `ERROR 1142` |
| `SELECT` no log da Aula 15 e `CREATE USER` | `ERROR 1142` e `ERROR 1227` |
| Trigger da Aula 15 ao editar voo | grava no log mesmo sem `GRANT` na tabela |
| Conta `relatorios`: `INSERT`, coluna `cpf`, view | `1142`, `1143`, view funciona |

Os detalhes e as mensagens completas estão no relatório.

## Checklist do enunciado

- [x] Conta do SGBD com privilégios mínimos
- [x] Conexão do PHP usando essa conta
- [x] `SHOW GRANTS` registrado
- [x] Tabela da Parte 3 com a mensagem do `DELETE`
- [x] Respostas da Parte 4
- [x] Desafio: erros do `INSERT` e da coluna `cpf`, e a alternativa com view
