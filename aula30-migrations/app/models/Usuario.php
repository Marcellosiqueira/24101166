<?php
// Usuarios que podem operar o sistema. Aula 25: login com e-mail e senha.

require_once __DIR__ . '/../../config/database.php';

class Usuario
{
    // Hash de uma senha qualquer, usado quando o e-mail nao existe: o
    // password_verify roda do mesmo jeito, e a resposta leva o mesmo tempo
    // para e-mail errado e senha errada.
    private const HASH_FALSO = '$2y$10$bakg5W0Cm0KLtFX3qZuagOrRanV830raScK.Dv3GDHxVdCuQd/jQO';

    private PDO $db;

    public function __construct()
    {
        $this->db = Database::conectar();
    }

    // Devolve id, nome e perfil se e-mail e senha conferem; senao, null.
    public function autenticar(string $email, string $senha): ?array
    {
        $stmt = $this->db->prepare(
            "SELECT id_usuario, nome, perfil, senha_hash FROM usuario WHERE email = :email"
        );
        $stmt->execute([':email' => $email]);
        $usuario = $stmt->fetch();

        if (!password_verify($senha, $usuario['senha_hash'] ?? self::HASH_FALSO) || !$usuario) {
            return null;
        }
        unset($usuario['senha_hash']);
        return $usuario;
    }
}
