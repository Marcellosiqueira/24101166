<?php
// Conexao centralizada: o unico arquivo do sistema que abre conexao com o banco.
// Credenciais vem do .env, que fica fora do Git e fora da pasta public/.

class Database
{
    private static ?PDO $conexao = null;

    public static function conectar(): PDO
    {
        if (self::$conexao === null) {
            $env = self::env();
            self::$conexao = new PDO(
                "mysql:host={$env['DB_HOST']};dbname={$env['DB_NAME']};charset=utf8mb4",
                $env['DB_USER'],
                $env['DB_PASS'],
                [
                    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                ]
            );
        }
        return self::$conexao;
    }

    // Le o .env com a funcao nativa parse_ini_file, sem biblioteca externa.
    public static function env(): array
    {
        static $env = null;
        if ($env === null) {
            $arquivo = __DIR__ . '/../.env';
            if (!is_file($arquivo)) {
                throw new RuntimeException('Arquivo .env nao encontrado. Copie o .env.example.');
            }
            $env = parse_ini_file($arquivo, false, INI_SCANNER_RAW);
        }
        return $env;
    }
}
