# Relatório: exclusão de voos com soft delete

Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

## Filtro de registros ativos

O filtro existe em um único lugar: a constante `Voo::ATIVO`, com o texto
`v.deleted_at IS NULL`. Todas as consultas de voo do model usam o alias `v` e
concatenam essa constante: `listar()`, `buscar()` e o `UPDATE` de `editar()`.
A única consulta que lê excluídos é `listarExcluidos()`, que usa a constante
`Voo::EXCLUIDO`. Controllers e views não têm SQL, então não há outro ponto onde o
filtro possa ser esquecido.

Como `editar()` e a tela de edição passam por `buscar()`, um voo excluído não pode
ser aberto nem alterado pelo id, mesmo que o id seja digitado na URL ou enviado
num POST. A tela de confirmação de exclusão também usa `buscar()`.

Duas proteções no banco completam o filtro do código:

- O índice único da Aula 10, `(id_rota, data_hora_partida)`, foi trocado por
  `(id_rota, data_hora_partida, ativo)`, em que `ativo` é uma coluna gerada que
  vale 1 para voo ativo e NULL para excluído. Um voo novo pode repetir rota e
  horário de um excluído, e dois ativos iguais continuam proibidos.
- O usuário `aeroporto_app` não tem mais o privilégio `DELETE`. Um `DELETE`
  esquecido no código é recusado pelo banco com o erro 1142.

## Atomicidade da exclusão com a auditoria

`excluir()` roda dentro de `transacao()`, que abre a transação, executa os passos
e faz `commit`; qualquer exceção leva ao `rollBack()`. Os passos são:

1. `SELECT ... FOR UPDATE` do voo ativo, que trava a linha e guarda o estado
   anterior para a auditoria;
2. contagem de passagens do voo, que recusa a exclusão se houver alguma;
3. `UPDATE voo SET deleted_at = NOW()`;
4. `INSERT` em `auditoria` com tabela, id, ação, usuário da sessão e o voo
   anterior em JSON.

Se o passo 4 falhar, o `rollBack()` desfaz o passo 3 e o voo continua ativo. O
teste `testes/rollback.php` comprova isso: uma subclasse do model faz o `INSERT`
de auditoria violar a chave estrangeira depois do `UPDATE`; dentro da transação o
voo aparece com `deleted_at` preenchido, e depois do erro volta a `NULL`, sem
linha de auditoria gravada. `restaurar()` segue o mesmo caminho com a ação
`restaurar`.

A auditoria fica no código e não numa trigger porque só a aplicação sabe qual
operador está na sessão; numa trigger, `CURRENT_USER()` seria sempre
`aeroporto_app`.
