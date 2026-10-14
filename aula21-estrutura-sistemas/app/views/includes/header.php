<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Aeroporto - Voos</title>
<link rel="stylesheet" href="css/style.css">
</head>
<body>
<header class="topo">
  <a href="index.php">Aeroporto</a>
</header>
<main class="conteudo">
<?php if (!empty($_SESSION['aviso'])): ?>
  <p class="aviso <?= htmlspecialchars($_SESSION['aviso']['tipo']) ?>"><?= htmlspecialchars($_SESSION['aviso']['texto']) ?></p>
  <?php unset($_SESSION['aviso']); ?>
<?php endif; ?>
<?php if (!empty($erro)): ?>
  <p class="aviso erro"><?= htmlspecialchars($erro) ?></p>
<?php endif; ?>
