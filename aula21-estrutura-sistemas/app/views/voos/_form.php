<?php $data = fn($v) => $v ? str_replace(' ', 'T', substr($v, 0, 16)) : ''; ?>
<div class="campos">
<label class="largo">Rota
  <select name="id_rota" required>
    <?php foreach ($rotas as $r): ?>
      <option value="<?= (int) $r['id_rota'] ?>" <?= ($dados['id_rota'] ?? '') == $r['id_rota'] ? 'selected' : '' ?>>
        <?= htmlspecialchars("{$r['numero_voo']} {$r['origem']} → {$r['destino']}") ?>
      </option>
    <?php endforeach; ?>
  </select>
</label>
<label class="largo">Aeronave
  <select name="id_aeronave" required>
    <?php foreach ($aeronaves as $a): ?>
      <option value="<?= (int) $a['id_aeronave'] ?>" <?= ($dados['id_aeronave'] ?? '') == $a['id_aeronave'] ? 'selected' : '' ?>>
        <?= htmlspecialchars("{$a['prefixo']} ({$a['modelo']}, {$a['capacidade_assentos']} assentos)") ?>
      </option>
    <?php endforeach; ?>
  </select>
</label>
<label>Partida
  <input type="datetime-local" name="data_hora_partida" required value="<?= htmlspecialchars($data($dados['data_hora_partida'] ?? '')) ?>">
</label>
<label>Chegada prevista
  <input type="datetime-local" name="data_hora_chegada_prevista" value="<?= htmlspecialchars($data($dados['data_hora_chegada_prevista'] ?? '')) ?>">
</label>
<label>Portão
  <input name="portao" maxlength="5" value="<?= htmlspecialchars($dados['portao'] ?? '') ?>">
</label>
<label>Status
  <select name="status">
    <?php foreach ($statusOpcoes as $s): ?>
      <option <?= ($dados['status'] ?? '') === $s ? 'selected' : '' ?>><?= htmlspecialchars($s) ?></option>
    <?php endforeach; ?>
  </select>
</label>
</div>
<div class="botoes">
  <button class="btn">Salvar</button>
  <a href="index.php">Cancelar</a>
</div>
