<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Aeroporto - Voos</title>
<link rel="stylesheet" href="css/style.css">
</head>
<body>
<h1><a href="index.php">Voos</a></h1>
<?php if (!empty($_SESSION['aviso'])): ?>
  <p class="<?= htmlspecialchars($_SESSION['aviso']['tipo']) ?>"><?= htmlspecialchars($_SESSION['aviso']['texto']) ?></p>
  <?php unset($_SESSION['aviso']); ?>
<?php endif; ?>
<?php if (!empty($erro)): ?>
  <p class="erro"><?= htmlspecialchars($erro) ?></p>
<?php endif; ?>
