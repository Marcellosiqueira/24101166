# Aula 22: Exclusão de voos com soft delete

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Continuação do CRUD de voos da Aula 21. Excluir um voo passa a preencher
`deleted_at` em vez de apagar a linha; o voo some das listagens, fica na tela
"Voos excluídos" e pode ser restaurado. Cada exclusão e restauração grava uma linha
de auditoria na mesma transação.

O relatório pedido no enunciado está em [`RELATORIO.md`](RELATORIO.md).

## O que mudou em relação à Aula 21

| Arquivo | Mudança |
| --- | --- |
| `banco/migration_soft_delete.sql` | coluna `deleted_at` com índice, índice único que ignora excluídos, tabelas `usuario` e `auditoria` |
| `banco/usuario_app.sql` | privilégios por tabela, sem `DELETE`; na auditoria, só `SELECT` e `INSERT` |
| `app/models/Voo.php` | filtro de ativos centralizado, `excluir()` e `restaurar()` em transação com auditoria, `listarExcluidos()` |
| `app/models/Usuario.php` | novo: lista os operadores |
| `app/controllers/VooController.php` | ações `confirmarExclusao`, `excluir`, `restaurar` e `excluidos` |
| `app/controllers/UsuarioController.php` | novo: entrar e sair |
| `app/views/voos/excluir.php` | novo: tela de confirmação |
| `app/views/voos/excluidos.php` | novo: tela "Voos excluídos" com botão de restaurar |
| `app/views/usuarios/entrar.php` | novo: escolha do operador |
| `public/index.php` | rotas novas; sem operador na sessão, só a tela de entrada abre |
| `testes/rollback.php` | novo: desafio 2 |
| `banco/desafio_backup.sh` | novo: desafio 3 |

## Como executar no Laragon

1. Rodar `aula10-integridade/sql_integridade.sql`. Opcionalmente,
   `aula15-triggers/triggers.sql`.
2. Rodar `banco/migration_soft_delete.sql` e depois `banco/usuario_app.sql`, como
   root.
3. Copiar `.env.example` para `.env` e conferir a senha.
4. Copiar a pasta para `C:\laragon\www\` e abrir
   `http://localhost/aula22-soft-delete/public/`.

Sem o Laragon, de dentro da pasta: `php -S localhost:8000 -t public`.

O `usuario_app.sql` desta aula tira o `DELETE` do usuário `aeroporto_app`. Se o
mesmo usuário for usado no projeto da Aula 21, a exclusão de lá passa a ser
recusada com o erro 1142.

## Quem excluiu

O projeto não tem autenticação. Para a auditoria saber quem agiu, o operador
escolhe o nome ao entrar (tabela `usuario`, três nomes de exemplo, sem senha) e o
id fica na sessão. Sem operador na sessão, qualquer rota cai na tela de entrada.

## Fluxo da exclusão

1. Na lista, "Excluir" abre a tela de confirmação com número, rota, partida e
   status do voo. Essa tela só exibe; é um GET.
2. "Confirmar exclusão" envia um POST. O model trava o voo, confere passagens,
   faz o `UPDATE` e grava a auditoria na mesma transação.
3. A página redireciona para a lista com a mensagem de sucesso ou de erro.

## Desafio 1: voo com passagens vendidas

Escolha: impedir a exclusão. A tela responde "Este voo tem 3 passagem(ns)
vendida(s) e não pode ser excluído. Para tirá-lo de operação, altere o status para
Cancelado."

Motivo: excluir em cascata deixaria passageiros com passagem de um voo que não
aparece em lugar nenhum, e cancelar passagens envolve reembolso ou remanejamento,
que o sistema não tem. O status Cancelado já existe para tirar o voo de operação
mantendo as passagens visíveis. Na Aula 21 quem recusava era o `ON DELETE RESTRICT`
da chave estrangeira; com soft delete não há `DELETE`, então a conferência foi para
dentro da transação. O `SELECT ... FOR UPDATE` no voo impede que uma passagem nova
seja vendida entre a contagem e o `UPDATE`.

## Desafio 2: falha no meio da exclusão

```bash
php testes/rollback.php 8
```

Saída:

```text
antes:  deleted_at = NULL, linhas de auditoria = 2
  dentro da transacao, depois do UPDATE: deleted_at = 2026-10-20 18:45:28
  erro devolvido ao controller: Não foi possível concluir a operação. Nada foi alterado.
  erro do banco: SQLSTATE[23000]: ... 1452 ... CONSTRAINT `fk_auditoria_usuario` ...
depois: deleted_at = NULL, linhas de auditoria = 2
OK: rollback desfez o UPDATE.
```

## Desafio 3: backup e restauração

```bash
sh banco/desafio_backup.sh 8
```

O script gera `backup_aeroporto.sql` com `mysqldump`, cria `aeroporto_teste` a partir
dele, apaga o voo 8 com `DELETE` e o recupera copiando a linha de um banco auxiliar
carregado com o mesmo backup. Restaurar o arquivo inteiro por cima também funcionaria,
mas desfaria tudo o que mudou depois do backup.

```text
Depois do DELETE:
voo_8
0
Depois da recuperacao:
id_voo  id_rota  data_hora_partida    status      deleted_at
8       1        2026-09-02 08:30:00  Aguardando  NULL
```

Diferença: pelo soft delete o voo volta com um clique, no estado exato em que estava,
e sem afetar mais nada, porque a linha nunca saiu da tabela. Pelo backup só volta o que
existia no momento do dump; alterações posteriores ao backup se perdem, e a
recuperação exige acesso de administrador ao banco.

## Teste

Rodado com PHP 8.3 e MySQL 8.0 contra o banco da Aula 10 com as triggers da Aula 15:

| Operação | Resultado |
| --- | --- |
| Abrir sem operador na sessão | tela de entrada, inclusive para POST de exclusão |
| Excluir voo 8 (sem passagens) | `deleted_at` preenchido, voo some da lista, auditoria com usuário e JSON do voo |
| Excluir por GET | 404 |
| Excluir de novo o voo 8 | "Voo não encontrado ou já excluído." |
| Editar o voo excluído pela URL e por POST | "Voo não encontrado." |
| Excluir voo 1 (3 passagens) | recusado; nada gravado |
| Cadastrar voo com rota e horário do voo excluído | aceito |
| Cadastrar o mesmo voo de novo | recusado: já existe voo ativo igual |
| Restaurar o 8 com o novo ativo | recusado; continua excluído |
| Excluir o novo e restaurar o 8 | aceito; auditoria com `excluir` e `restaurar` |
| `DELETE FROM voo` como `aeroporto_app` | erro 1142 |
| `UPDATE auditoria` como `aeroporto_app` | erro 1142 |

## Checklist do enunciado

- [x] Migration com `deleted_at DATETIME NULL DEFAULT NULL`
- [x] `excluir($id)` com `UPDATE`, nunca `DELETE`
- [x] Todas as listagens e buscas filtrando `deleted_at IS NULL`
- [x] `restaurar($id)` voltando `deleted_at` para `NULL`
- [x] Ação de excluir com confirmação e mensagem de retorno
- [x] Auditoria na mesma transação, com rollback se falhar
- [x] Tela "Voos excluídos" com botão de restaurar
- [x] Índice em `deleted_at` e índice único que não colide com excluídos
- [x] Desafios 1, 2 e 3
