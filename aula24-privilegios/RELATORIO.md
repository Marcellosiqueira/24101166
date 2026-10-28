# Aula 24: Privilégios no projeto do aeroporto

Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Executado em MySQL 8.0.46 e PHP 8.3, sobre o banco das Aulas 10, 15, 22 e 23.

## Adaptação ao projeto

O projeto já não usava `root` desde a Aula 21: a conexão era a conta `aeroporto_app`,
que nas Aulas 22 e 23 perdeu o `DELETE`. Nesta aula a conta passa a ter o nome do
enunciado, `app_aeroporto`, que vai ser usada nas próximas aulas, e o `.env.example`
aponta para ela. O arquivo de conexão (`config/database.php`) não mudou: usuário e
senha vêm do `.env`, como o enunciado recomenda para um sistema real.

A tabela do enunciado é `voos`; no projeto é `voo`, e a tela de voos lê também `rota`,
`aeronave`, `modelo_aeronave` e `passagem` (contagem de passagens antes de excluir). A
auditoria da Aula 22 grava em `auditoria`, e o operador vem de `usuario`. Cada uma
recebeu só o que a aplicação usa.

## Parte 1: SHOW GRANTS

```text
GRANT USAGE ON *.* TO `app_aeroporto`@`localhost`
GRANT SELECT ON `aeroporto`.`aeronave` TO `app_aeroporto`@`localhost`
GRANT SELECT, INSERT ON `aeroporto`.`auditoria` TO `app_aeroporto`@`localhost`
GRANT SELECT ON `aeroporto`.`modelo_aeronave` TO `app_aeroporto`@`localhost`
GRANT SELECT ON `aeroporto`.`passagem` TO `app_aeroporto`@`localhost`
GRANT SELECT ON `aeroporto`.`rota` TO `app_aeroporto`@`localhost`
GRANT SELECT ON `aeroporto`.`usuario` TO `app_aeroporto`@`localhost`
GRANT SELECT, INSERT, UPDATE ON `aeroporto`.`voo` TO `app_aeroporto`@`localhost`
```

`USAGE` significa só "pode conectar". Não há `DELETE` em nenhuma tabela, nem privilégio
global, nem acesso a outro banco.

## Parte 3: CRUD com a conta nova

| Operação | Esperado | O que aconteceu |
| --- | --- | --- |
| Listar voos (`SELECT`) | funciona | 8 voos listados |
| Criar voo (`INSERT`) | funciona | voo 9 gravado, "Voo cadastrado" |
| Editar voo (`UPDATE`) | funciona | portão e status do voo 9 alterados, "Voo atualizado" |
| Excluir voo pela aplicação | funciona | "Voo excluído", `deleted_at` preenchido no voo 9 |
| `DELETE` direto no banco | erro | `ERROR 1142 (42000): DELETE command denied to user 'app_aeroporto'@'localhost' for table 'voo'` |
| `DROP TABLE voo` | erro | `ERROR 1142 (42000): DROP command denied to user 'app_aeroporto'@'localhost' for table 'voo'` |

O botão Excluir da aplicação continua funcionando porque o projeto usa soft delete desde
a Aula 22: excluir é `UPDATE voo SET deleted_at = NOW()`. Quem impede apagar a linha de
verdade é a conta sem `DELETE`, e não o botão da tela. Se algum código novo tentar um
`DELETE`, o banco recusa com 1142 e o model mostra a mensagem genérica, com o detalhe
só em `logs/erros.log`.

Dois testes a mais com a conta:

| Comando | Resultado |
| --- | --- |
| `SELECT ... FROM log_alteracao_voo` | `ERROR 1142`: SELECT negado na tabela de log da Aula 15 |
| `CREATE USER x@localhost` | `ERROR 1227`: falta o privilégio CREATE USER |

### Efeito nas triggers da Aula 15

A conta não tem nenhum privilégio em `log_alteracao_voo`, e mesmo assim a edição do voo
9 gravou duas linhas de log. As triggers rodam com os privilégios de quem as criou
(`root`), não de quem disparou o `UPDATE`.

Isso trouxe um achado: a coluna `usuario` do log registrou `root@localhost`, e não
`app_aeroporto`. A trigger usa `CURRENT_USER()`, como o enunciado da Aula 15 pedia, e
dentro de uma trigger essa função devolve o dono da trigger. Para registrar a conta que
fez o `UPDATE`, a função seria `USER()`. Enquanto a conexão era a mesma conta que criou
as triggers, a diferença não aparecia. A Aula 15 não foi alterada; o registro fica aqui.

## Parte 4: Discussão

**1. O que mudou para a Maria e o que mudou para a conexão?**
Para a Maria, nada. Ela continua entrando com o mesmo cadastro da tabela de usuários e
vendo as mesmas telas, porque ela é usuária da aplicação e não conta do MySQL. O que
mudou foi a conexão: todas as consultas da aplicação, de qualquer usuário, agora passam
por uma conta que só pode ler e escrever nas tabelas listadas acima.

**2. Quem decide se a Maria pode excluir um voo?**
O código PHP. O banco não sabe quem é a Maria: ele só vê a conta `app_aeroporto`, a
mesma para todos os usuários. A permissão por perfil é regra da aplicação. O banco
define o teto do que a aplicação inteira pode fazer, e dentro desse teto o PHP decide o
que cada usuário pode.

**3. O que um atacante faria com uma SQL Injection agora, e com root?**
Agora ele ficaria limitado aos privilégios da conta: ler as tabelas concedidas, inserir
e alterar voos, inserir linhas de auditoria. Não conseguiria apagar dados, derrubar
tabelas, criar contas nem ler outros bancos. Ainda conseguiria ler `email` e
`senha_hash` de `usuario`, porque a aplicação precisa dessa leitura, o que é mais um
motivo para a senha estar em hash. Com `root`, teria tudo: apagar o banco inteiro, ler
as contas do servidor em `mysql.user`, criar uma conta para voltar depois e, se o
servidor permitir, gravar arquivos em disco.

## Desafio: conta só de leitura

Script em `banco/desafio_relatorios.sql`. A tabela do enunciado é `passageiros`; no
projeto é `passageiro`, com chave `id_passageiro`.

| Passo | Comando com a conta `relatorios` | Resultado |
| --- | --- | --- |
| 1 | `SELECT COUNT(*) FROM voo` | 9 |
| 1 | `INSERT INTO voo ...` | `ERROR 1142 (42000): INSERT command denied to user 'relatorios'@'localhost' for table 'voo'` |
| 3 | `SELECT id_passageiro, nome FROM passageiro` | funciona |
| 3 | `SELECT cpf FROM passageiro` | `ERROR 1143 (42000): SELECT command denied to user 'relatorios'@'localhost' for column 'cpf' in table 'passageiro'` |
| 3 | `SELECT * FROM passageiro` | `ERROR 1142`: o `*` inclui colunas sem privilégio, então a tabela inteira é negada |
| 3 | `SELECT COUNT(*) FROM voo` | `ERROR 1142`: o `REVOKE` tirou a leitura do resto do banco |
| 4 | `SELECT * FROM vw_passageiro_relatorio` | funciona, só `id_passageiro` e `nome` |

`SHOW GRANTS` depois do script inteiro:

```text
GRANT USAGE ON *.* TO `relatorios`@`localhost`
GRANT SELECT (`id_passageiro`, `nome`) ON `aeroporto`.`passageiro` TO `relatorios`@`localhost`
GRANT SELECT ON `aeroporto`.`vw_passageiro_relatorio` TO `relatorios`@`localhost`
```

A view resolve o problema do `SELECT *`: quem consulta a view vê uma tabela com só as
duas colunas, e `SELECT *` funciona. A view roda com os privilégios de quem a criou,
então a conta lê a view sem ter privilégio na tabela.
