# Aula 23: SQL Injection

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Continuação do sistema de voos da Aula 22. A busca de voos por destino foi feita em
duas versões, uma sem e outra com prepared statement, e os quatro payloads do
enunciado foram aplicados nas duas. Depois dos testes a versão vulnerável foi removida,
como pede o enunciado; o código testado está no commit `7ce614a`
(`git show 7ce614a -- aula23-sql-injection/app`).

A tabela de comparação e as respostas das três perguntas, que são a entrega do
Moodle, estão em [`RELATORIO.md`](RELATORIO.md).

## O que mudou em relação à Aula 22

| Arquivo | Mudança |
| --- | --- |
| `banco/migration_sql_injection.sql` | novo: `email` e `senha_hash` em `usuario`, com dados de teste |
| `app/models/Voo.php` | `buscarSeguro()`; `buscarVulneravel()` existiu no commit `7ce614a` e foi removido |
| `app/controllers/VooController.php` | ação `buscar`; no commit `7ce614a` ela escolhia a versão por `versao` |
| `app/views/voos/buscar.php` | novo: formulário de destino e tabela com as 5 colunas |
| `app/views/includes/header.php` | link "Buscar" no menu |
| `public/index.php` | rota GET `buscar` |
| `config/database.php` | `PDO::ATTR_EMULATE_PREPARES => false` |

O relatório e os scripts dos desafios da Aula 22 ficaram só na pasta dela.

## Como executar no Laragon

1. Se o banco ainda não tem a Aula 22: rodar `aula10-integridade/sql_integridade.sql`,
   opcionalmente `aula15-triggers/triggers.sql`, e `banco/migration_soft_delete.sql`
   (cópia do da Aula 22).
2. Rodar `banco/migration_sql_injection.sql` e depois `banco/usuario_app.sql`, como
   root.
3. Copiar `.env.example` para `.env` e conferir a senha.
4. Copiar a pasta para `C:\laragon\www\`, abrir
   `http://localhost/aula23-sql-injection/public/`, entrar com um operador e clicar em
   "Buscar".

Sem o Laragon, de dentro da pasta: `php -S localhost:8000 -t public`.

A URL do enunciado funciona depois de entrar. O parâmetro `versao` não tem mais efeito:
toda busca usa o prepared statement.

```text
index.php?acao=buscar&versao=a&destino=BSB
```

Para refazer os ataques na versão A, voltar a pasta para o commit do laboratório:

```bash
git checkout 7ce614a -- aula23-sql-injection/app
```

## Adaptações ao projeto

- `destino` está em `rota` e é código IATA, então as consultas fazem `JOIN` e o
  controle usa `BSB` no lugar de `Lisboa`.
- A tabela é `usuario`, não `usuarios`, e a chave é `id_usuario`. O payload 4 ficou
  `x' UNION SELECT id_usuario, email, senha_hash, 4, 5 FROM usuario -- `.
- As duas versões filtram `deleted_at IS NULL`, como toda consulta de voo desde a
  Aula 22.
- O `listar.php` usa colunas que a busca não devolve (prefixo, partida, portão), por
  isso a busca tem view própria.

## Decisões fora do enunciado

**Prepare real no banco.** O PDO do MySQL, por padrão, só emula o prepare: escapa o
valor no PHP e manda um texto único. No log geral do MySQL a versão B aparecia como
`Query ... r.destino = '\' OR \'1\'=\'1'`. A injeção já não funcionava, mas comando e
dado chegavam juntos. Com `ATTR_EMULATE_PREPARES => false` o log passou a mostrar
`Prepare ... r.destino = ?` e depois `Execute`. A mudança vale para o sistema todo, e o
CRUD da Aula 22 foi testado de novo com ela (tabela abaixo).

**Dados de teste em `usuario`.** A tabela da Aula 22 só tinha nome. As colunas novas
aceitam NULL para a migração rodar sobre um banco com usuários já cadastrados; os três
usuários de exemplo recebem email e hash bcrypt.

## Teste

PHP 8.3 e MySQL 8.4, conectado como `aeroporto_app`, contra o banco da Aula 10 com as
triggers da Aula 15 e a migração da Aula 22. Antes dos ataques o voo 8 foi excluído pela
tela (soft delete).

Ataques: resultados no [`RELATORIO.md`](RELATORIO.md).

Regressão do CRUD com `ATTR_EMULATE_PREPARES => false`:

| Operação | Resultado |
| --- | --- |
| Cadastrar voo novo | "Voo cadastrado." |
| Cadastrar o mesmo voo de novo | "Já existe um voo ativo desta rota com a mesma data e hora de partida." |
| Chegada antes da partida | "A chegada prevista precisa ser depois da partida." |
| Trocar a aeronave do voo 1 pela PT-TST | "Troca recusada: voo 1 tem 3 passagens, aeronave 7 tem 2 assentos" |
| Excluir voo 1 (3 passagens) | recusado; `deleted_at` continua NULL |
| Excluir e restaurar o voo 8 | aceito; auditoria com `excluir` e `restaurar` |
| Editar o voo 8 | rota e status gravados no banco |
| Excluir por GET | 404 |
| Buscar sem operador na sessão | tela de entrada |
| `versao=zzz` com o payload 3, no commit `7ce614a` | versão B, 0 resultados |
| Os quatro payloads com `versao=a`, depois da remoção | 0 resultados nos payloads 2, 3 e 4; o `BSB` devolve os voos de BSB |

## Checklist do enunciado

- [x] Dados de teste em voos e usuários
- [x] `buscarVulneravel()` sem prepared statement
- [x] `buscarSeguro()` com prepared statement
- [x] Controller escolhendo a versão por `versao`
- [x] Quatro payloads nas duas versões
- [x] Tabela de comparação preenchida
- [x] Respostas das três perguntas
- [x] Remover `buscarVulneravel()` depois dos testes
