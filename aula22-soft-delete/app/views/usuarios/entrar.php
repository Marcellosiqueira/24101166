<div class="cabecalho">
  <h1>Entrar</h1>
</div>
<form class="formulario" method="post" action="index.php?acao=autenticar">
  <p class="nota">Escolha seu nome. Exclusões e restaurações ficam registradas na auditoria com ele.</p>
  <div class="campos">
    <label class="largo">Operador
      <select name="id_usuario" required>
        <?php foreach ($usuarios as $u): ?>
          <option value="<?= (int) $u['id_usuario'] ?>"><?= htmlspecialchars($u['nome']) ?></option>
        <?php endforeach; ?>
      </select>
    </label>
  </div>
  <div class="botoes">
    <button class="btn">Entrar</button>
  </div>
</form>
