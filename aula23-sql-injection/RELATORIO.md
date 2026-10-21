# Aula 23: SQL Injection no sistema do Aeroporto

Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

## Adaptação ao projeto

A busca por destino roda sobre o esquema normalizado da Aula 10: `destino` e
`numero_voo` ficam em `rota`, então as duas versões fazem `JOIN` de `voo` com `rota` e
filtram só voos ativos (`deleted_at IS NULL`, da Aula 22). As cinco colunas são as do
enunciado: `id`, `numero_voo`, `origem`, `destino`, `status`.

O destino é código IATA (`ck_rota_destino_iata`), por isso a busca de controle usa `BSB`
em vez de `Lisboa`. A tabela de usuários se chama `usuario` e ganhou `email` e
`senha_hash` (`banco/migration_sql_injection.sql`). O payload 4 ficou:

```text
x' UNION SELECT id_usuario, email, senha_hash, 4, 5 FROM usuario -- 
```

## Comparação

Executado em PHP 8.3 e MySQL 8.4, conectado como `aeroporto_app`, com `APP_DEBUG=0`.
Havia 8 voos, um deles (id 8, destino BSB) excluído por soft delete antes dos testes.

| Payload | Versão A (sem prepared) | Versão B (com prepared) |
| --- | --- | --- |
| 1 `BSB` | 2 voos (305 e 308) | 2 voos (305 e 308) |
| 2 `'` | HTTP 500, "Erro interno". No log: erro 1064, sintaxe SQL inválida. Com `APP_DEBUG=1` a tela mostra a mensagem do MySQL | 0 resultados, sem erro |
| 3 `' OR '1'='1` | 8 voos, todos os destinos, **inclusive o voo 8 excluído** | 0 resultados |
| 4 `UNION ...` | 3 linhas com id, email e hash bcrypt dos três usuários, nas colunas de número e origem | 0 resultados |

No payload 3 a versão A ignorou também o filtro de soft delete. A consulta virou
`WHERE v.deleted_at IS NULL AND r.destino = '' OR '1'='1'`; como `AND` tem precedência
sobre `OR`, a condição `'1'='1'` sozinha basta para qualquer linha passar.

O que o MySQL recebeu, capturado no log geral do servidor (payload 3):

```text
Versão A
  Prepare  ... WHERE v.deleted_at IS NULL AND r.destino = '' OR '1'='1'
Versão B
  Prepare  ... WHERE v.deleted_at IS NULL AND r.destino = ?
  Execute  ... WHERE v.deleted_at IS NULL AND r.destino = '\' OR \'1\'=\'1'
```

No `Execute` o log mostra o valor já encaixado no lugar do `?` só para leitura; na rede
o valor vai separado do comando.

## Respostas

**1. Por que a versão B se comporta diferente com o mesmo texto de entrada?**

Na versão B o texto nunca passa pelo analisador de SQL. O comando é compilado antes, com
um `?` no lugar do destino, e o texto chega depois como valor de uma coluna `CHAR(3)`.
`' OR '1'='1` vira só um destino que não existe, e a busca devolve zero linhas.

**2. O que o banco recebe como comando e o que recebe como dado em cada versão?**

Na versão A o banco recebe um único texto, e tudo nele é comando, inclusive o que o
usuário digitou: a aspa fecha o literal, o `OR` e o `UNION` viram SQL e o `--` comenta o
resto. Na versão B o comando é a consulta com `?` (mensagem `Prepare`) e o dado é o valor
enviado à parte (mensagem `Execute`), que o banco nunca interpreta.

Por padrão o PDO do MySQL só emula o prepare: escapa as aspas no PHP e manda um texto
único (no log apareceu `r.destino = '\' OR \'1\'=\'1'`). Também protege, mas a separação
não acontece no banco. Por isso `config/database.php` passou a usar
`PDO::ATTR_EMULATE_PREPARES => false`; o log acima é com essa opção.

**3. Se só a versão A existisse em produção, qual seria o pior dano do payload 4?**

O payload 4 entrega email e hash de senha de todos os usuários para qualquer pessoa com
acesso à tela de busca. Com os hashes, o atacante tenta quebrar as senhas offline, sem
limite de tentativas, e entra como operador; com os emails, faz phishing ou testa as
mesmas senhas em outros serviços. O mesmo método lê qualquer tabela que o
`aeroporto_app` possa ler, como os localizadores das passagens. O privilégio mínimo da
Aula 22 limita o estrago: sem `DELETE`, sem acesso a outros bancos e sem `FILE`, o ataque
não apaga dados nem lê arquivos do servidor. Restringir o `SELECT` em `usuario` às
colunas que a aplicação usa barra este payload com erro 1143 (testado com
`GRANT SELECT (id_usuario, nome)`).
