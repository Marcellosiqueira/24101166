<?php
// Protecao das paginas. Como todo acesso passa por public/index.php, um unico
// require ali protege todas as telas de voos (listar, criar, editar, excluir).

function exigirLogin(): void
{
    if (empty($_SESSION['usuario_id'])) {
        header('Location: index.php?acao=entrar');
        exit;
    }
}

// Desafio: exclusao so para admin. Os demais recebem 403.
function exigirAdmin(): void
{
    if (($_SESSION['usuario']['perfil'] ?? '') !== 'admin') {
        http_response_code(403);
        exit('Acesso negado: só o perfil admin pode excluir ou restaurar voos.');
    }
}

function ehAdmin(): bool
{
    return ($_SESSION['usuario']['perfil'] ?? '') === 'admin';
}
