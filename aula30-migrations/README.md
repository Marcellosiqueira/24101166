# Aula 30: Migrations

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Continuação do sistema de voos da Aula 25. A aula pede um runner de migrations com
`up` e `down` e uma tabela de controle, uma primeira migration real (`portao_embarque`) e
a renomeação de `origem` para `aeroporto_origem` pelo padrão expandir e contrair, sem
parar o sistema. Tudo roda no banco de teste `aeroporto_lab`, cópia do `aeroporto` feita
com `mysqldump`. As respostas das Perguntas 1 e 2 e da Parte 4 estão em `respostas.md`.

## Entregáveis

| Arquivo | Conteúdo |
| --- | --- |
| `migrate.php` | runner: `up`, `up <versão>` e `down` |
| `migrations/001_baseline.sql` | ponto de partida (`SELECT 1`) |
| `migrations/002_add_portao_embarque.sql` | `portao_embarque` em `voo` |
| `migrations/003_add_aeroporto_origem.sql` | expandir: `aeroporto_origem CHAR(3)` em `rota`, com as `CHECK` |
| `migrations/003a_vw_painel_voos_aeroporto_origem.sql` | `vw_painel_voos` lendo a coluna nova |
| `migrations/004_drop_origem.sql` | contrair: remove as `CHECK` antigas e `rota.origem` |
| `backfill_origem.php` | cópia de `origem` para `aeroporto_origem` em lotes de 1000 |
| `reset_lab.sql` | recria o `aeroporto_lab` do dump, com a view e os privilégios |
| `banco/view_painel_voos.sql` | `vw_painel_voos` da Aula 14, como era antes das migrations |
| `schema_migrations.txt` | saída de `SELECT * FROM schema_migrations` depois de aplicar tudo |
| `respostas.md` | Perguntas 1 e 2 e as quatro da Parte 4 |

## O que mudou em relação à Aula 25

| Arquivo | Mudança |
| --- | --- |
| `migrate.php`, `migrations/`, `backfill_origem.php`, `reset_lab.sql` | novos |
| `banco/view_painel_voos.sql` | novo: view da Aula 14 para o lab |
| `.env.example` | `DB_NAME=aeroporto_lab`; `MIGRATE_USER` e `MIGRATE_PASS` para migrations e backfill |
| `.gitignore` | `aeroporto_backup.sql` e `*.log` |
| `banco/usuario_app.sql` | mesmos privilégios da Aula 25, agora em `aeroporto_lab` |
| `app/models/Voo.php` | lê só `aeroporto_origem`; o `INSERT` em `rota` gravou nos dois campos (3a) e depois só no novo (3c) |
| `app/views/voos/_form.php` | campo `aeroporto_origem` no lugar de `origem` |
| `app/views/voos/listar.php`, `excluidos.php`, `excluir.php`, `buscar.php` | exibem `aeroporto_origem` |

Os scripts `banco/migration_*.sql` das Aulas 22 a 25 foram mantidos como estavam. Eles
montam o `aeroporto` de que o `aeroporto_lab` é copiado.

## Como executar no Laragon

No terminal do Laragon (que já tem `php` e `mysql` no PATH), dentro de
`C:\laragon\www\24101166\aula30-migrations`:

1. Dump do banco do projeto, uma vez, como o enunciado manda:

   ```bash
   mysqldump -u root aeroporto > aeroporto_backup.sql
   ```

2. Banco de teste. O `reset_lab.sql` apaga e recria o `aeroporto_lab` a partir do dump,
   cria a `vw_painel_voos` da Aula 14 (`banco/view_painel_voos.sql`) e roda
   `banco/usuario_app.sql`. Depois dele o lab está pronto para a 001, e ele pode ser
   rodado de novo a qualquer momento para recomeçar:

   ```bash
   mysql -u root < reset_lab.sql
   ```

3. Copiar `.env.example` para `.env` e pôr a senha do `app_aeroporto` em `DB_PASS`.
4. Migrations em ordem, com o backfill no meio:

   ```bash
   php migrate.php up 003_add_aeroporto_origem
   php backfill_origem.php
   php migrate.php up
   ```

   O primeiro comando aplica 001, 002 e 003. O último aplica 003a e 004, que só devem
   rodar depois do backfill e do código novo (ver decisões).
5. Abrir `http://localhost/24101166/aula30-migrations/public/` e entrar com
   `ana.ribeiro@aeroporto.test` / `ana2026` (admin).

Para o teste da Parte 2: `php migrate.php up 002_add_portao_embarque`, `php migrate.php
down` e o mesmo `up` de novo.

## Adaptações ao esquema

**1. `voos.origem` vira `rota.origem`.** No esquema normalizado da Aula 09, número do
voo, origem e destino ficam em `rota`; `voo` só aponta para ela. A 003, a 004 e o backfill
são em `rota`. Como `origem` é código IATA `CHAR(3)`, `aeroporto_origem` também é
`CHAR(3)`, não `VARCHAR(80)`.

**2. As `CHECK` de `origem`.** `rota.origem` tem `ck_rota_origem_destino` e
`ck_rota_origem_iata`. Com elas, o `DROP COLUMN` falha: testei numa tabela descartável e
veio `ERROR 3959: Check constraint 'ck_t' uses column 'origem', hence column cannot be
dropped or renamed`. As equivalentes em `aeroporto_origem`
(`ck_rota_aeroporto_origem_destino` e `ck_rota_aeroporto_origem_iata`) são criadas na
003, no mesmo `ALTER TABLE` que cria a coluna, porque a partir do passo 3c só a coluna
nova é gravada e as `CHECK` antigas não a protegem. A 004 só remove as duas antigas e a
coluna. Cada seção é um único `ALTER TABLE` com várias cláusulas, o que conta como uma
instrução. O `down` da 003 remove as `CHECK` novas junto com a coluna; o `down` da 004
recria as antigas em `origem`.

**3. A view da Aula 14.** `vw_painel_voos` lê `r.origem` e ficaria inválida depois da
004. A migration `003a_vw_painel_voos_aeroporto_origem` recria a view lendo
`r.aeroporto_origem AS origem` (quem consulta a view continua vendo a coluna `origem`). O
nome `003a` fica depois da `003` e antes da `004` tanto no `sort()` do `up` quanto no
`ORDER BY version DESC` do `down`, então o `down` desfaz a 004 antes de voltar a view. O
`down` da 003a recria a view com `r.origem`.

**4. Triggers da Aula 15.** Nenhuma das oito cita `rota.origem`. As três ocorrências de
"origem" em `triggers.sql` são comentários. Nada a tratar.

**5. `portao_embarque` em `voo`.** A tabela já tem `portao` desde a Aula 10.
`portao_embarque` é a coluna do exercício, e nenhum código a usa, o que é o ponto da
Pergunta 1.

**6. Credenciais do `.env`.** `migrate.php` e `backfill_origem.php` leem o `.env` com o
mesmo `Database::env()` do resto do projeto. O `.env` aponta para `aeroporto_lab`. Eles
usam `MIGRATE_USER` e `MIGRATE_PASS`, e não `DB_USER`, porque a conta `app_aeroporto`
não tem `ALTER`, `CREATE VIEW` nem `UPDATE` em `rota`, e não deve ter.

**7. Passo 3 no PHP.** Primeiro o `INSERT` em `rota` do `Voo.php` passou a gravar
`origem` e `aeroporto_origem`. O `UPDATE` de voo não toca em `rota` (a aplicação nunca
altera rota, só cria), então o único ponto de gravação é esse `INSERT`. Depois as
consultas do model (`listar`, `listarExcluidos`, `buscar`, `buscarSeguro`,
`resolverRota`), o formulário e as views passaram a ler só `aeroporto_origem`. Em
`banco/usuario_app.sql` não havia privilégio por coluna para o `app_aeroporto`, só por
tabela, então a coluna nova já está coberta e nada citava `rota.origem`. A conta
`relatorios` da Aula 24 tem privilégio por coluna só em `passageiro`, que não muda.

## Decisões fora do enunciado

- **Runner: `query()->closeCursor()` no lugar de `exec()`.** O runner do enunciado falhou
  já na 001: o `SELECT 1` executado com `exec()` deixa o resultado pendente, e o
  `INSERT` em `schema_migrations` logo depois dá `SQLSTATE[HY000]: General error: 2014
  Cannot execute queries while other unbuffered queries are active`. A 001 não ficou
  registrada. Com `query()` e `closeCursor()` o resultado é descartado e funciona para
  `SELECT`, `ALTER` e `CREATE VIEW`.
- **`php migrate.php up <versão>`.** O `up` do enunciado aplica todas as pendentes. Com
  os arquivos todos na pasta, isso aplicaria 003, 003a e 004 de uma vez, sem backfill
  nem troca de código no meio. O segundo argumento para na versão dada. São três linhas.
- **A 003 deixa `origem` aceitar NULL.** O código que grava nos dois campos quebraria
  depois da 004, porque `origem` não existe mais. O código que grava só em
  `aeroporto_origem` quebraria antes dela, porque `origem` era `NOT NULL`. Com `origem`
  NULL a partir da 003, dá para trocar o código (passo 3c) antes da 004 sem nenhum
  momento de cadastro quebrado.
- **Passo 3c.** Depois de testar o código que grava nos dois campos e lê só o novo, o
  `INSERT` em `rota` deixou de gravar `origem`. É a versão entregue. Ela funciona tanto
  antes quanto depois da 004.
- **`CHECK` na 003.** Ver a adaptação 2: sem elas, entre o passo 3c e a 004 uma rota
  com origem igual ao destino passaria no banco. Testado antes da 004: `BSB → BSB` e
  `bs1` gravando só `aeroporto_origem` foram recusados com erro 3819.
- **A 004 recusa rodar sem backfill.** A primeira cláusula da 004 é `MODIFY
  aeroporto_origem CHAR(3) NOT NULL`, como `origem` era. Testei com uma rota sem
  backfill: o `up` falhou com `1138 Invalid use of NULL value`, a 004 não foi registrada
  e `origem` continuou na tabela.
- **Campo do formulário renomeado para `aeroporto_origem`.** O passo 3 pede que os
  formulários leiam só a coluna nova; o nome do campo acompanha a coluna.
- **`reset_lab.sql` e `banco/view_painel_voos.sql`.** O `aeroporto` do meu Laragon não
  tinha a view da Aula 14, então ela vai para o lab num arquivo próprio, e o reset junta
  dump, view e privilégios num comando só.

## Teste

MySQL 8.4.3 e PHP 8.3.33 do Laragon, banco `aeroporto_lab`. Aplicação no servidor
embutido do PHP, conectada como `app_aeroporto`. Testes da aplicação com `curl` e
cookie de sessão, e no navegador depois da 004.

Os resultados são da execução completa a partir do `reset_lab.sql`, com os arquivos
finais, exceto os marcados com "desenvolvimento" (runner original, Pergunta 1, erro 3959
e código na fase 3a), que vieram de uma primeira execução feita antes do reset.

### Migrations

| Teste | Resultado |
| --- | --- |
| `up` da 001 com o runner do enunciado (`exec()`) | erro 2014; nada registrado (desenvolvimento) |
| `reset_lab.sql` | 7 rotas, sem `schema_migrations`, view com `LA305 GRU BSB` |
| `up` da 001 com `query()->closeCursor()` | `Aplicada: 001_baseline`; 1 linha em `schema_migrations` |
| `up` da 002 e `DESCRIBE voo portao_embarque` | `portao_embarque varchar(5) YES` |
| `down` e `DESCRIBE` | `Desfeita: 002_add_portao_embarque`; `DESCRIBE` vazio |
| `up` da 002 de novo | coluna de volta |
| Pergunta 1: coluna `NOT NULL` sem `DEFAULT` e `INSERT` como o do app | `ALTER` passa, linhas antigas com `''`; `INSERT` dá erro 1364 (desenvolvimento) |
| `up` da 003 | `origem` e `aeroporto_origem` `char(3) YES`; 7 NULL; 4 `CHECK` com "origem" |
| `backfill_origem.php` | `Lote: 7 linhas`, `Lote: 0 linhas` |
| `COUNT(*) WHERE aeroporto_origem IS NULL` | 0 |
| `INSERT` só em `aeroporto_origem`, `BSB → BSB` / `bs1`, antes da 004 | 3819 em `ck_rota_aeroporto_origem_destino` / `_iata` |
| `up` da 003a | view com `LA420 BSB GIG`, `LA305 GRU BSB` |
| `DROP COLUMN` com `CHECK` (tabela descartável) | erro 3959 (desenvolvimento) |
| `up` da 004 com uma rota sem backfill | recusado (1138); `origem` continua; 004 não registrada |
| `up` da 004 depois de apagar essa rota | `Aplicada: 004_drop_origem`; `rota` sem `origem`, `aeroporto_origem NOT NULL`, só as 2 `CHECK` novas |
| `down` da 004 (Pergunta 2) | 9 rotas, as 9 com `origem` NULL; `CHECK` antigas de volta |
| Recuperação pelo `aeroporto_backup.sql`, logo depois do `down` | 7 recuperadas; `LA911` e `LA912` continuam NULL |
| `up` da 004 de novo e `up` sem pendentes | `Aplicada: 004_drop_origem`; depois nenhuma saída |

### Aplicação

| Teste | fase 3a, antes da 004 (desenvolvimento) | código final, antes da 004 | depois da 004 |
| --- | --- | --- | --- |
| Lista com `origem` do LA305 trocada para `ZZZ` | mostra `GRU`: lê `aeroporto_origem` | não repetido | não se aplica |
| Listar | HTTP 200 | HTTP 200 | HTTP 200 |
| Criar `LA9xx bsb → poa` | "Voo cadastrado."; `origem BSB`, `aeroporto_origem BSB` | "Voo cadastrado."; `origem NULL`, `aeroporto_origem BSB` | "Voo cadastrado."; `aeroporto_origem BSB` |
| Criar na rota existente `LA305 GRU → BSB` | "Voo cadastrado." | igual | igual |
| Origem = destino | "A origem precisa ser diferente do destino." | igual | igual |
| IATA inválido `B1S` | "Origem e destino devem ser códigos de aeroporto com 3 letras" | igual | igual |
| `LA305` com origem `CNF` | "O voo LA305 já está cadastrado como GRU → BSB." | igual | igual |
| Abrir edição | HTTP 200, campo com `BSB` | igual | igual |
| Editar portão `7B`, status Confirmado | "Voo atualizado."; banco `7B Confirmado` | igual | igual |
| Confirmar exclusão | HTTP 200, `BSB → POA` | igual | igual |
| Excluir (admin) | "Voo excluído..."; `deleted_at` preenchido | igual | igual |
| Excluídos e busca por destino | HTTP 200, origem exibida | igual | igual |
| `GET` em `salvar`, `excluir`, `atualizar` | HTTP 404 | HTTP 404 | HTTP 404 |
| `logs/erros.log` | vazio | vazio | vazio |

Os erros de origem igual ao destino e de IATA inválido são pegos pelo `validar()` do
model antes de chegar ao banco; o teste de `INSERT` direto acima mostra a `CHECK` da 003
pegando o mesmo caso por fora da aplicação. No navegador, no estado final: `LA913
GIG → GIG` recusado com "A origem precisa ser diferente do destino." e `LA913 GIG → CWB`
cadastrado ("Voo cadastrado.") e exibido na lista com a origem.

## Checklist do enunciado

- [x] Cópia `aeroporto_lab` criada com `mysqldump` (`aeroporto_backup.sql` fora do Git)
- [x] `migrate.php` com `schema_migrations`, `up` e `down`
- [x] `001_baseline` aplicada; checkpoint com uma linha
- [x] `002_add_portao_embarque`: up, `DESCRIBE`, down, up de novo
- [x] Pergunta 1 respondida
- [x] Passo 1: `003_add_aeroporto_origem`
- [x] Passo 2: `backfill_origem.php` em lotes; checkpoint com 0
- [x] Passo 3: código grava nos dois campos, depois lê só `aeroporto_origem`; listar, criar, editar e excluir testados
- [x] Passo 4: `004_drop_origem` aplicada depois do código novo
- [x] Pergunta 2: `down` da 004 executado e resultado registrado
- [x] Parte 4: lag, ordem, imutabilidade e backup
- [x] Saída de `schema_migrations` em `schema_migrations.txt`
- [x] `respostas.md`
