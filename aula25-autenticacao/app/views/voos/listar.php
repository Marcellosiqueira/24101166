<div class="cabecalho">
  <h1>Voos</h1>
  <a class="btn" href="index.php?acao=criar">Novo voo</a>
</div>

<?php if (!$voos): ?>
  <p class="vazio">Nenhum voo cadastrado.</p>
<?php else: ?>
<div class="tabela-rolagem">
<table>
  <thead>
    <tr><th>Número</th><th>Rota</th><th>Aeronave</th><th>Partida</th><th>Portão</th><th>Status</th><th class="acoes">Ações</th></tr>
  </thead>
  <tbody>
  <?php foreach ($voos as $v): ?>
    <tr>
      <td class="mono forte"><?= htmlspecialchars($v['numero_voo']) ?></td>
      <td class="mono"><?= htmlspecialchars($v['origem']) ?> <span class="seta">→</span> <?= htmlspecialchars($v['destino']) ?></td>
      <td class="mono"><?= htmlspecialchars($v['prefixo']) ?></td>
      <td><?= htmlspecialchars(date('d/m/Y H:i', strtotime($v['data_hora_partida']))) ?></td>
      <td class="mono"><?= ($v['portao'] ?? '') !== '' ? htmlspecialchars($v['portao']) : '<span class="tracos">-</span>' ?></td>
      <td><span class="status-<?= htmlspecialchars(strtolower($v['status'])) ?>"><?= htmlspecialchars($v['status']) ?></span></td>
      <td class="acoes">
        <a href="index.php?acao=editar&id=<?= (int) $v['id_voo'] ?>">Editar</a>
        <?php if (ehAdmin()): ?>
          <a class="perigo" href="index.php?acao=confirmar_exclusao&id=<?= (int) $v['id_voo'] ?>">Excluir</a>
        <?php endif; ?>
      </td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
<?php endif; ?>
