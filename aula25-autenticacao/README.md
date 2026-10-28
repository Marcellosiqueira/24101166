# Aula 25: Autenticação e validação

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Continuação do sistema de voos da Aula 24. O sistema passa a exigir login com e-mail e
senha, valida o cadastro de voo no servidor e não mostra erro de banco na tela. O
desafio, exclusão só para o perfil `admin`, também foi feito.

O arquivo do professor se chama "Aula 25" e o título interno diz "Aula 27"; a pasta
segue o nome do arquivo.

## O que mudou em relação à Aula 24

| Arquivo | Mudança |
| --- | --- |
| `banco/migration_autenticacao.sql` | novo: `perfil` em `usuario`, código dos voos no formato `LA1234` |
| `banco/usuario_app.sql` | `INSERT` em `rota` para `app_aeroporto` |
| `app/auth.php` | novo: `exigirLogin()`, `exigirAdmin()` e `ehAdmin()` |
| `app/models/Usuario.php` | `autenticar()` com prepared statement e `password_verify` |
| `app/controllers/UsuarioController.php` | login por e-mail e senha, logout com `session_destroy()` |
| `app/models/Voo.php` | `validar()`, criação da rota pelo código digitado, mensagem genérica de erro |
| `app/controllers/VooController.php` | lista `$erros`, 403 para quem não é admin |
| `app/views/usuarios/entrar.php` | formulário de e-mail e senha |
| `app/views/voos/_form.php` | código, origem e destino digitados; lista de erros |
| `app/views/voos/listar.php`, `excluidos.php` | Excluir e Restaurar só aparecem para admin |
| `public/index.php` | `require` de `auth.php`; cookie de sessão `httponly` e `SameSite=Lax` |

## Como executar no Laragon

1. Se o banco ainda não tem a Aula 23: rodar `aula10-integridade/sql_integridade.sql`,
   opcionalmente `aula15-triggers/triggers.sql`, `banco/migration_soft_delete.sql` e
   `banco/migration_sql_injection.sql` (cópias das Aulas 22 e 23).
2. Rodar `banco/migration_autenticacao.sql` e depois `banco/usuario_app.sql`, como root.
3. Copiar `.env.example` para `.env` e conferir a senha.
4. Copiar a pasta para `C:\laragon\www\` e abrir
   `http://localhost/aula25-autenticacao/public/`.

Usuários de teste (senhas gravadas como hash bcrypt desde a Aula 23):

| E-mail | Senha | Perfil |
| --- | --- | --- |
| `ana.ribeiro@aeroporto.test` | `ana2026` | admin |
| `bruno.teixeira@aeroporto.test` | `bruno2026` | operador |
| `carla.mendes@aeroporto.test` | `carla2026` | operador |

Para gerar o hash de outra senha: `php -r "echo password_hash('senha123', PASSWORD_DEFAULT);"`.

## Adaptações ao projeto

**Tabela de usuários.** A do enunciado é `usuarios`; no projeto é `usuario`, criada na
Aula 22 e com `email` e `senha_hash` desde a Aula 23. A migração só acrescenta `perfil`,
com `CHECK` para `operador` ou `admin`, e torna e-mail e senha obrigatórios.

**Proteção das páginas.** O enunciado coloca `require 'auth.php'` no topo de cada
página. Aqui toda requisição passa por `public/index.php`, então um único
`exigirLogin()` ali protege listar, criar, editar e excluir. A sessão guarda
`$_SESSION['usuario_id']`, como no enunciado.

**Código do voo.** Até a Aula 24 o formulário escolhia uma rota cadastrada numa lista, e
os códigos eram só números (`305`). A validação pedida (duas letras e 3 ou 4 números,
origem diferente de destino) só faz sentido se o usuário digita esses campos. Por isso:

- a migração trocou os códigos para `LA305`, `LA420` etc. (prefixo do exemplo do
  enunciado) e criou a constraint `ck_rota_numero_voo` com o mesmo formato;
- o formulário recebe código, origem e destino digitados;
- se o código já existe, o voo usa aquela rota; se não, a rota é criada. O mesmo código
  com outra origem ou destino é recusado ("O voo LA305 já está cadastrado como
  GRU → BSB"), o que mantém a premissa da normalização da Aula 09: um código é sempre
  a mesma rota.

**Partida no futuro.** Exigida só no cadastro. Os voos da carga de dados já partiram, e
na edição o operador precisa continuar podendo mudar status e portão de um voo que já
saiu.

## Decisões fora do enunciado

- **Tempo igual para e-mail e senha errados.** Quando o e-mail não existe, o
  `password_verify` roda contra um hash falso. Sem isso, e-mail inexistente responderia
  mais rápido, e a diferença de tempo revelaria quais e-mails estão cadastrados mesmo
  com a mensagem igual.
- **`FOR UPDATE` retirado da busca de rota.** No MySQL 8, `SELECT ... FOR UPDATE` exige
  privilégio `UPDATE` na tabela, e a conta não altera rota. O teste mostrou o erro 1142
  no log. Se dois usuários criarem o mesmo código ao mesmo tempo, o segundo esbarra no
  `UNIQUE` de `numero_voo` e recebe uma mensagem pedindo para tentar de novo.
- **Restaurar voo também é só para admin.** Restaurar desfaz uma exclusão, então segue
  a mesma regra do desafio.
- **Validação no servidor e constraint no banco.** As regras de formato e de origem
  diferente de destino estão no `validar()` do model e também no banco
  (`ck_rota_numero_voo`, `ck_rota_origem_destino`). A tela usa a do model, que devolve a
  lista completa de erros de uma vez; a do banco vale para quem gravar por fora da
  aplicação.

## Teste

MySQL 8.0.46 e PHP 8.3, aplicação conectada como `app_aeroporto`:

| Teste | Resultado |
| --- | --- |
| Abrir lista, cadastro ou `POST` de salvar sem login | redireciona para `?acao=entrar` |
| Senha errada / e-mail inexistente | "E-mail ou senha inválidos" nos dois casos |
| Login correto | redireciona para a lista; o id da sessão muda |
| Código `L123`, origem = destino, partida no passado | os três erros listados juntos |
| Código `LA12345`, origem `BS`, sem partida | os três erros listados juntos |
| `LA305` com origem e destino diferentes dos cadastrados | recusado com a rota existente |
| `la1234 bsb → poa` válido | voo gravado, rota `LA1234` criada em maiúsculas |
| `LA305 GRU → BSB` válido | voo gravado na rota existente |
| Editar voo com partida no passado | gravado |
| Operador abre confirmação ou envia exclusão | HTTP 403 |
| Lista para operador / para admin | 0 / 10 links Excluir |
| Admin exclui | "Voo excluído" |
| Tabela `voo` renomeada e salvar | tela: "Não foi possível salvar o voo."; log: erro 1146 |
| Rota criada nesse salvar com erro | nenhuma: a transação desfez |
| Sair e abrir a lista | redireciona para o login |
| `GET` em `autenticar` | HTTP 404 |

## Checklist do enunciado

- [x] Senhas gravadas como hash, nunca em texto puro
- [x] Login funciona e a mensagem de erro é a mesma para e-mail ou senha errados
- [x] Páginas de voos redirecionam para o login quando não há sessão
- [x] Logout encerra a sessão
- [x] Voo inválido é rejeitado com mensagem clara
- [x] Erro de banco não aparece na tela e é registrado no log
- [x] Desafio: exclusão só para `admin`, 403 para os demais
