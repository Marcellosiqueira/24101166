<?php
// Porta unica de entrada. O servidor aponta para public/, entao config/, app/
// e .env nao tem URL.

session_start();
require_once __DIR__ . '/../app/controllers/VooController.php';
require_once __DIR__ . '/../app/controllers/UsuarioController.php';

$debug = (Database::env()['APP_DEBUG'] ?? '0') === '1';
ini_set('display_errors', $debug ? '1' : '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/../logs/erros.log');

// Acoes que alteram dados so aceitam POST.
$rotas = [
    'GET'  => [
        'listar'    => [VooController::class, 'listar'],
        'buscar'    => [VooController::class, 'buscar'],
        'excluidos' => [VooController::class, 'excluidos'],
        'criar'     => [VooController::class, 'criar'],
        'editar'    => [VooController::class, 'editar'],
        'confirmar_exclusao' => [VooController::class, 'confirmarExclusao'],
        'entrar'    => [UsuarioController::class, 'entrar'],
    ],
    'POST' => [
        'salvar'    => [VooController::class, 'salvar'],
        'atualizar' => [VooController::class, 'atualizar'],
        'excluir'   => [VooController::class, 'excluir'],
        'restaurar' => [VooController::class, 'restaurar'],
        'autenticar' => [UsuarioController::class, 'autenticar'],
        'sair'      => [UsuarioController::class, 'sair'],
    ],
];

$acao = $_GET['acao'] ?? 'listar';
$rota = $rotas[$_SERVER['REQUEST_METHOD']][$acao] ?? null;

if ($rota === null) {
    http_response_code(404);
    exit('Página não encontrada.');
}

// Sem operador identificado, so a tela de entrada funciona: a auditoria
// precisa saber quem excluiu.
if (empty($_SESSION['usuario']) && $rota[0] !== UsuarioController::class) {
    $rota = [UsuarioController::class, 'entrar'];
}

try {
    [$classe, $metodo] = $rota;
    (new $classe())->$metodo();
} catch (Throwable $e) {
    error_log($e->getMessage());
    http_response_code(500);
    echo $debug ? htmlspecialchars($e->getMessage()) : 'Erro interno. Tente novamente.';
}
