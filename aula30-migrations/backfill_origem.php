<?php
// Passo 2 da Parte 3: copia rota.origem para rota.aeroporto_origem em lotes.
// Uso: php backfill_origem.php (depois da 003)
// A aplicacao nao tem UPDATE em rota, entao usa a conta das migrations.

require __DIR__ . '/config/database.php';

$env = Database::env();
$pdo = new PDO(
    "mysql:host={$env['DB_HOST']};dbname={$env['DB_NAME']};charset=utf8mb4",
    $env['MIGRATE_USER'],
    $env['MIGRATE_PASS'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

do {
    $afetadas = $pdo->exec(
        "UPDATE rota SET aeroporto_origem = origem
          WHERE aeroporto_origem IS NULL
          LIMIT 1000"
    );
    echo "Lote: $afetadas linhas\n";
    usleep(200000); // pausa de 0,2 s para nao sobrecarregar o banco
} while ($afetadas > 0);
