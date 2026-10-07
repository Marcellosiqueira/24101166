// Funcoes de apresentacao usadas pelas duas versoes.

const formatarNota = nota =>
    nota.toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 2 });

// Monta as linhas com textContent, e nao com innerHTML: o nome vem do banco,
// e um nome contendo HTML seria interpretado pela pagina se fosse concatenado.
function preencherTabela(alunos, calcularStatus) {
    const corpo = document.querySelector('#alunos tbody');
    corpo.replaceChildren();

    for (const aluno of alunos) {
        const status = calcularStatus(aluno);
        const linha = corpo.insertRow();
        linha.insertCell().textContent = aluno.nome;
        linha.insertCell().textContent = formatarNota(aluno.nota);
        const celulaStatus = linha.insertCell();
        celulaStatus.textContent = status;
        celulaStatus.className = status === 'Aprovado' ? 'aprovado' : 'reprovado';
    }
}

function carregar(url, calcularStatus) {
    const aviso = document.getElementById('aviso');
    fetch(url)
        .then(resposta => {
            if (!resposta.ok) throw new Error('HTTP ' + resposta.status);
            return resposta.json();
        })
        .then(alunos => {
            preencherTabela(alunos, calcularStatus);
            aviso.textContent = alunos.length + ' alunos carregados de ' + url;
        })
        .catch(erro => {
            console.error('Erro:', erro);
            aviso.textContent = 'Nao foi possivel carregar os alunos.';
        });
}
