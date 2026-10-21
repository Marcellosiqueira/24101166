<div class="cabecalho">
  <h1>Buscar voos por destino</h1>
</div>

<form class="formulario" method="get" action="index.php">
  <input type="hidden" name="acao" value="buscar">
  <div class="campos">
    <label>Destino (código IATA)
      <input name="destino" value="<?= htmlspecialchars($destino) ?>">
    </label>
  </div>
  <div class="botoes"><button class="btn">Buscar</button></div>
</form>

<?php if ($destino !== ''): ?>
  <p class="nota"><?= count($voos) ?> resultado(s).</p>
  <?php if ($voos): ?>
  <div class="tabela-rolagem">
  <table>
    <thead><tr><th>Id</th><th>Número</th><th>Origem</th><th>Destino</th><th>Status</th></tr></thead>
    <tbody>
    <?php foreach ($voos as $v): ?>
      <tr>
        <td class="mono"><?= htmlspecialchars($v['id']) ?></td>
        <td class="mono forte"><?= htmlspecialchars($v['numero_voo']) ?></td>
        <td class="mono"><?= htmlspecialchars($v['origem']) ?></td>
        <td class="mono"><?= htmlspecialchars($v['destino']) ?></td>
        <td><?= htmlspecialchars($v['status']) ?></td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
  </div>
  <?php endif; ?>
<?php endif; ?>
