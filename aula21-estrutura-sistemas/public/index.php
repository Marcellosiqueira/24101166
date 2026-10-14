<?php
// Porta unica de entrada. O servidor aponta para public/, entao config/, app/
// e .env nao tem URL.

session_start();
require_once __DIR__ . '/../app/controllers/VooController.php';

$debug = (Database::env()['APP_DEBUG'] ?? '0') === '1';
ini_set('display_errors', $debug ? '1' : '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/../logs/erros.log');

// Acoes que alteram dados so aceitam POST.
$rotas = [
    'GET'  => ['listar' => 'listar', 'criar' => 'criar', 'editar' => 'editar'],
    'POST' => ['salvar' => 'salvar', 'atualizar' => 'atualizar', 'excluir' => 'excluir'],
];

$acao   = $_GET['acao'] ?? 'listar';
$metodo = $rotas[$_SERVER['REQUEST_METHOD']][$acao] ?? null;

if ($metodo === null) {
    http_response_code(404);
    exit('Página não encontrada.');
}

try {
    (new VooController())->$metodo();
} catch (Throwable $e) {
    error_log($e->getMessage());
    http_response_code(500);
    echo $debug ? htmlspecialchars($e->getMessage()) : 'Erro interno. Tente novamente.';
}
