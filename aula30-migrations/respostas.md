# Aula 30: respostas

Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

As respostas usam o que aconteceu nos testes no `aeroporto_lab` (MySQL 8.4.3 do Laragon,
`sql_mode` com `STRICT_TRANS_TABLES`). No projeto a tabela é `voo` e a origem fica em
`rota`, então onde o enunciado diz `voos.origem` aqui é `rota.origem`.

## Pergunta 1: `portao_embarque` como `NOT NULL` sem valor padrão

O cadastro de voo pararia de funcionar. Testei com uma coluna descartável
`teste_nn VARCHAR(5) NOT NULL` em `voo`:

- o `ALTER TABLE` passou, e as linhas antigas receberam o valor implícito `''`;
- o `INSERT` igual ao do `Voo::criar()`, que não cita a coluna nova, falhou com
  `ERROR 1364: Field 'teste_nn' doesn't have a default value`.

Na tela, o model não traduz o 1364, então o usuário veria "Não foi possível salvar o voo."
e o erro iria para o log. Listar, editar e excluir continuariam funcionando, porque o
`SELECT` e o `UPDATE` não citam a coluna. Criando a coluna como `NULL`, o código antigo
continua gravando, e só o código novo passa a preencher `portao_embarque`.

## Pergunta 2: o `down` da 004 traz os dados de volta?

Não. Na execução a partir do `reset_lab.sql`, o banco tinha 9 rotas no momento do
`down`: as 7 do dump e 2 criadas pelos testes da aplicação (`LA911` antes da 004 e
`LA912` depois). O `down` recriou a coluna `origem` e as duas `CHECK` antigas, mas as 9
ficaram com `origem` NULL. Em uma frase: o `down` desfaz a estrutura, mas não consegue
recriar os valores apagados pelo `DROP COLUMN`, que faz commit implícito e não tem
rollback; para recuperar, eu restauraria o `aeroporto_backup.sql` em um banco separado e
copiaria `origem` de volta com um `UPDATE ... JOIN` pela chave `id_rota`.

Testei essa recuperação logo depois do `down`: o `UPDATE rota l JOIN
aeroporto_restore.rota b ON b.id_rota = l.id_rota SET l.origem = b.origem` recuperou 7
linhas, as 7 do dump. `LA911` e `LA912` continuaram NULL, mas não perderam nada: foram
criadas pelo código final, que já não grava `origem`, então nunca tiveram valor nessa
coluna. Neste caso o valor ainda existe em `aeroporto_origem`, e `UPDATE rota SET origem
= aeroporto_origem` também recuperaria as 7, mas isso só vale porque a renomeação copiou
os dados antes; numa remoção de coluna comum, o que foi gravado depois do backup se
perde.

## Parte 4: e se houvesse réplicas?

### 1. Lag

Um `UPDATE` sem `LIMIT` em 5 milhões de linhas vira uma transação única. No primário, ela
trava as linhas até o commit (gravações da aplicação nessas linhas esperam ou caem em
`lock wait timeout`), enche o undo log e disputa o buffer pool com as consultas normais. O
binlog só recebe a transação no commit, então as réplicas começam a aplicá-la depois que
o primário terminou e levam um tempo parecido para aplicar. Durante esse tempo a réplica
fica atrasada em tudo, não só nessa tabela, e quem lê dela vê `aeroporto_origem` vazio.
Em lotes de 1000 com pausa, cada lote é uma transação curta: trava pouco, replica logo e
o atraso fica pequeno. No nosso banco o backfill fez dois lotes (7 linhas e 0 linhas).
No esquema normalizado o backfill é em `rota`, uma linha por código de voo, e não em
`voo`, o que já reduz muito o volume. O `UPDATE ... LIMIT` sem `ORDER BY` só é seguro
com binlog em formato `ROW` (o padrão do MySQL 8); em `STATEMENT`, primário e réplica
poderiam escolher linhas diferentes.

### 2. Ordem

Depois do passo 1 porque o código novo cita `aeroporto_origem`; se ele subir antes da
coluna existir, cada consulta falha com erro 1054 (`Unknown column`), o mesmo erro que o
script de teste recebeu ao pedir `origem` depois da 004. Com réplicas, o código só sobe
depois que a 003 chegou a todas elas. Antes do passo 4 porque o código antigo lê e grava
`origem`; se a coluna sumir com ele no ar, listagem e cadastro quebram. No projeto foi
preciso ir além: o código que grava nos dois campos também quebraria depois da 004, então
antes dela o `INSERT` em `rota` deixou de gravar `origem` (passo 3c no README). Isso só
foi possível porque a 003 deixou `origem` aceitar NULL.

### 3. Imutabilidade

O runner decide o que aplicar pela `version` em `schema_migrations`. Nos ambientes onde a
`002` já está registrada, editar o arquivo não muda nada: a coluna continua com 5. Só
ambientes novos teriam 10, os bancos ficariam diferentes com o mesmo histórico, e o
arquivo deixaria de descrever o que foi executado. A correção é uma migration nova:

```sql
-- 005_alter_portao_embarque_tamanho.sql
-- up
ALTER TABLE voo MODIFY portao_embarque VARCHAR(10) NULL;

-- down
ALTER TABLE voo MODIFY portao_embarque VARCHAR(5) NULL;
```

O `down` dela falha (erro 1406, `Data too long`) se algum portão com mais de 5
caracteres já tiver sido gravado. Essa `005` não foi criada na pasta: ela responde a um
cenário hipotético.

### 4. Backup

O passo 4. O `DROP COLUMN` apaga os valores, e o `down` só recria a coluna vazia, como o
teste da Pergunta 2 mostrou. Os outros passos têm volta sem backup: o passo 1 só
acrescenta uma coluna (o `down` a remove), o passo 2 só preenche a coluna nova e não
toca em `origem`, e o passo 3 é código, que se desfaz voltando a versão anterior. No
teste, das 9 rotas que ficaram com `origem` NULL, o backup devolveu as 7 que existiam
quando o dump foi feito; as outras 2 nunca tiveram `origem`. Por isso o backup precisa ser
feito logo antes da 004: qualquer valor gravado em `origem` depois do dump estaria
perdido.
