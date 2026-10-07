<?php
// Conexao com o banco. Valores padrao do Laragon: root sem senha em localhost.
// Pode ser sobrescrito por variaveis de ambiente sem mexer no codigo.
function conectar(): PDO
{
    $host  = getenv('DB_HOST') ?: '127.0.0.1';
    $banco = getenv('DB_NAME') ?: 'aula20';
    $user  = getenv('DB_USER') ?: 'root';
    $senha = getenv('DB_PASS') ?: '';

    return new PDO("mysql:host=$host;dbname=$banco;charset=utf8mb4", $user, $senha, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
}

// Responde JSON e encerra. Em caso de erro, devolve status 500 com mensagem
// generica: o detalhe da excecao fica no log do servidor, nao vai para o cliente.
function responder(callable $consulta): void
{
    header('Content-Type: application/json; charset=utf-8');
    try {
        echo json_encode($consulta(conectar()), JSON_UNESCAPED_UNICODE);
    } catch (Throwable $e) {
        error_log($e->getMessage());
        http_response_code(500);
        echo json_encode(['erro' => 'Falha ao consultar os alunos']);
    }
}
