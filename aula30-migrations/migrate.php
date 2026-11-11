<?php
// Runner de migrations da Aula 30, versao minima do enunciado.
// Uso: php migrate.php up          (aplica as pendentes)
//      php migrate.php up 003_x    (aplica as pendentes ate a versao 003_x)
//      php migrate.php down        (desfaz a ultima aplicada)
//
// Credenciais do .env, como o resto do projeto. A migration altera estrutura,
// entao usa MIGRATE_USER e MIGRATE_PASS; a conta app_aeroporto (DB_USER) nao
// tem ALTER nem CREATE VIEW.

require __DIR__ . '/config/database.php';

$env = Database::env();
$pdo = new PDO(
    "mysql:host={$env['DB_HOST']};dbname={$env['DB_NAME']};charset=utf8mb4",
    $env['MIGRATE_USER'],
    $env['MIGRATE_PASS'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$pdo->exec("CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(100) PRIMARY KEY,
    aplicada_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");

// Separa o arquivo em duas partes: antes e depois da linha "-- down"
function separar(string $sql): array {
    $partes = preg_split('/^-- down\s*$/m', $sql);
    return [trim($partes[0]), trim($partes[1] ?? '')];
}

$comando = $argv[1] ?? 'up';
$ate     = $argv[2] ?? null;

if ($comando === 'up') {
    $aplicadas = $pdo->query("SELECT version FROM schema_migrations")
                     ->fetchAll(PDO::FETCH_COLUMN);
    $arquivos = glob(__DIR__ . '/migrations/*.sql');
    sort($arquivos);

    foreach ($arquivos as $arquivo) {
        $versao = basename($arquivo, '.sql');
        if ($ate !== null && strcmp($versao, $ate) > 0) {
            break;
        }
        if (in_array($versao, $aplicadas)) {
            continue;
        }
        [$up] = separar(file_get_contents($arquivo));
        // query() + closeCursor() em vez de exec(): com exec(), o SELECT 1 da
        // 001 deixa o resultado pendente e o INSERT abaixo falha (erro 2014).
        $pdo->query($up)->closeCursor();
        $pdo->prepare("INSERT INTO schema_migrations (version) VALUES (?)")
            ->execute([$versao]);
        echo "Aplicada: $versao\n";
    }
} elseif ($comando === 'down') {
    $ultima = $pdo->query(
        "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1"
    )->fetchColumn();

    if (!$ultima) {
        echo "Nada a desfazer.\n";
        exit;
    }
    [, $down] = separar(file_get_contents(__DIR__ . "/migrations/$ultima.sql"));
    $pdo->query($down)->closeCursor();
    $pdo->prepare("DELETE FROM schema_migrations WHERE version = ?")
        ->execute([$ultima]);
    echo "Desfeita: $ultima\n";
}
