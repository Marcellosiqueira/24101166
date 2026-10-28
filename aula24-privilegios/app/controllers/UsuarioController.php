<?php
// Entrada e saida do operador. Guarda id e nome na sessao para a auditoria.

require_once __DIR__ . '/../models/Usuario.php';

class UsuarioController
{
    public function entrar(): void
    {
        $usuarios = (new Usuario())->listar();
        require __DIR__ . '/../views/includes/header.php';
        require __DIR__ . '/../views/usuarios/entrar.php';
        require __DIR__ . '/../views/includes/footer.php';
    }

    public function autenticar(): void
    {
        $usuario = (new Usuario())->buscar((int) ($_POST['id_usuario'] ?? 0));
        if ($usuario !== null) {
            session_regenerate_id(true);
            $_SESSION['usuario'] = $usuario;
        }
        header('Location: index.php');
        exit;
    }

    public function sair(): void
    {
        $_SESSION = [];
        session_regenerate_id(true);
        header('Location: index.php');
        exit;
    }
}
