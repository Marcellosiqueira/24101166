<?php
// Usuarios que podem operar o sistema. Sem senha: o projeto nao tem
// autenticacao, e a escolha do nome serve para a auditoria saber quem agiu.

require_once __DIR__ . '/../../config/database.php';

class Usuario
{
    private PDO $db;

    public function __construct()
    {
        $this->db = Database::conectar();
    }

    public function listar(): array
    {
        return $this->db->query("SELECT id_usuario, nome FROM usuario ORDER BY nome")->fetchAll();
    }

    public function buscar(int $id): ?array
    {
        $stmt = $this->db->prepare("SELECT id_usuario, nome FROM usuario WHERE id_usuario = :id");
        $stmt->execute([':id' => $id]);
        return $stmt->fetch() ?: null;
    }
}
