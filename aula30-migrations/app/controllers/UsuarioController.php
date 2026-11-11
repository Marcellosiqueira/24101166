<?php
// Login e logout.

require_once __DIR__ . '/../models/Usuario.php';

class UsuarioController
{
    public function entrar(array $variaveis = []): void
    {
        extract($variaveis);
        require __DIR__ . '/../views/includes/header.php';
        require __DIR__ . '/../views/usuarios/entrar.php';
        require __DIR__ . '/../views/includes/footer.php';
    }

    public function autenticar(): void
    {
        $email = trim($_POST['email'] ?? '');
        $usuario = (new Usuario())->autenticar($email, $_POST['senha'] ?? '');

        if ($usuario === null) {
            // Mesma mensagem para e-mail e senha errados: a tela nao revela
            // quais e-mails estao cadastrados.
            $this->entrar(['erro' => 'E-mail ou senha inválidos', 'email' => $email]);
            return;
        }

        // Novo id de sessao no login: um id plantado antes do login nao vale
        // depois dele (fixacao de sessao).
        session_regenerate_id(true);
        $_SESSION['usuario_id'] = (int) $usuario['id_usuario'];
        $_SESSION['usuario']    = ['nome' => $usuario['nome'], 'perfil' => $usuario['perfil']];
        header('Location: index.php');
        exit;
    }

    public function sair(): void
    {
        $_SESSION = [];
        setcookie(session_name(), '', time() - 3600, '/');
        session_destroy();
        header('Location: index.php?acao=entrar');
        exit;
    }
}
