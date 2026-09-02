# PENDINGS.md

Open items left behind by executed plans. **Every plan writes here.** When a plan
finishes and something is knowingly not done — deferred, blocked, gated on a decision,
or accepted as-is — it lands in this file instead of only in a chat message that
nobody will find again.

## How to use it

- **One section per plan/slice**, newest first. Keep the plan file path so the context
  is recoverable.
- Every entry states **what is pending, why it was not done, and what unblocks it**.
  "Why" is the part that saves the next person from re-deriving the decision.
- Mark each entry with a status:
  - `OPEN` — needs doing.
  - `GATED` — blocked on a decision or an external condition; name the gate.
  - `ACCEPTED` — knowingly left as-is; not a bug, do not re-flag it.
- Delete an entry when it is genuinely resolved. Do not leave a graveyard of DONEs.
- A pending that touches another slice's domain is **recorded here, not fixed
  unilaterally** — flag it and let the owner decide.

### Write them short

This file is read when someone is about to work, not for pleasure. Density beats prose.

- **Target: 3–6 lines per entry.** If it needs more, the entry is really two entries, or it
  belongs in the plan/spec — link there instead of re-explaining.
- **Drop the connective tissue.** No "it is worth noting that", no restating the title in the
  first sentence, no paragraph of background before the point.
- **Three facts, that is the whole shape**: what is pending · why it was not done · what
  unblocks it. Anything that is not one of the three is cut.
- **Keep every identifier, number, path and error string exact.** Terse means fewer words, never
  vaguer facts. `403 on getMarketplaceParticipations` survives; "an auth problem" does not.
- **No credential-rotation chores.** Secret hygiene is handled outside this file — do not add
  "rotate X" items here.

---

## session-end router, fork lane e propagação das skills (2026-09-02)

Planos: `docs/superpowers/plans/2026-09-02-session-end-router-fork-lane.md` ·
`docs/superpowers/plans/2026-09-02-skill-propagation.md`

### `OPEN` — o run completo da session-end carrega 45% mais que o monólito que substituiu

Medido 2026-09-02: monólito 36.761 bytes · roteador 8.943 · run docs-only 25.280 (−31%) ·
**run completo 53.599 (+45%)**. A quebra baratear o caso parcial e encareceu o completo, porque
o corpo cresceu 21 achados. Já foram movidos ~6,0 KB de material com gatilho para
`skills/session-end/references/traps.md`. Sobram **~3 KB** roteando a tabela de triagem do Step 1
atrás de um ponteiro `gate red →`; isso é uma segunda quebra e não foi feita.
Exposição: um close-out completo custa mais contexto que antes, numa skill cujo propósito é rodar
quando contexto está escasso.

### `OPEN` — `.claude/` não está no `.gitignore` e guarda as worktrees

`git check-ignore -v .claude/worktrees` não devolve nada. `.gitignore:5` tem `.claude.json`, que
casa com um `grep ^\.claude` ingênuo e não ignora diretório nenhum. Um `git add -A` neste repo
empacota worktrees inteiras. Achado por falso positivo de grep e re-medido com `git check-ignore`,
que é o check capaz de falhar na afirmação.
**`__pycache__/` tem o mesmo buraco e foi medido no close-out**: rodar os próprios gates de Python
do repo (`python -m py_compile` sobre `skills/**/*.py` e `scripts/**/*.py`) suja a árvore em três
diretórios, e nada os ignora. Quem roda os gates do repo tem de limpar à mão.
Conserto: duas linhas, `.claude/worktrees/` e `__pycache__/`.
Não feito no run que os encontrou: fora da superfície das duas specs, e esta skill fecha trabalho.

### `OPEN` — o `CLAUDE.md` publicado está atrás do vivo

O `CLAUDE.md` deste repo não tem o parágrafo de exceção que o global vivo carrega — o que diz que
invocar uma skill cujos passos incluem PR e merge **é** o pedido explícito. Sem ele, um leitor do
repo público lê as três proibições sem a saída. Medido 2026-09-02 comparando o arquivo do repo com
`~/.claude/CLAUDE.md`. `scripts/check-drift.sh` **não pega isso**: ele varre `skills/` apenas.
Unblock: copiar o parágrafo, e decidir se o check-drift passa a cobrir `CLAUDE.md` e `RTK.md`.

### `OPEN` — três arquivos violam o `.gitattributes` no próprio banco de objetos

Achado pelo `scripts/check-drift.sh --repo-only` na **primeira execução real dele**, sobre a `main`
já mergeada. `skills/code-ultragraph-review/lib/codex-refine.sh` e `lib/verify.sh` estão commitados
com CRLF contra `*.sh text eol=lf`; `hooks/reap-orphans.ps1` tem finais mistos contra
`*.ps1 text eol=crlf`. Quebra o shebang em macOS/Linux, que é o motivo pelo qual o `.gitattributes`
existe.
Laneado `pre-existing-on-base` por **identidade de blob**: `git rev-parse b85ee86:<f>` e
`HEAD:<f>` devolvem o mesmo hash nos três, e nenhuma das quatro branches deste run toca esses
arquivos. Não é regressão do merge.
**`git archive` é o instrumento errado aqui** — ele aplica o `eol` do `.gitattributes` na
exportação, então reproduzir por export devolve "limpo" e esconde a condição. Use `git cat-file blob`.
Unblock: `git add --renormalize` nesses caminhos, em commit próprio. Não feito aqui: esta skill
fecha trabalho, não abre, e os arquivos pertencem a uma skill que este run não tocou.

### `ACCEPTED` — a fork lane da session-end sai sem nunca ter rodado

`skills/session-end/steps/lane-fork-orchestrator.md`. Nenhum close-out real de N≥2 a exercitou e
nada neste repo consegue exercitá-la. Está dito no texto do próprio arquivo.
Raio de alcance: só a lane — as lanes inline e sequencial não mudaram e são as que rodam hoje.

### `ACCEPTED` — duas provas que não se reproduzem fora desta máquina

`python3` aqui é o stub da Microsoft Store: existe no PATH, imprime "Python nao foi encontrado" e
sai 49; `python` é 3.12.10 real. Todo resolvedor escrito exige a string exata `PY_OK` em vez de
confiar em nome ou exit code. Num Linux o fallback nunca é exercitado.
E a contagem de `check-drift.sh` é uma **leitura**, não propriedade. Eram 5 antes destes merges;
medida na `main` mergeada às 09:2xZ são **34 linhas**, quase todas `ONLY IN REPO` sob
`session-end/verify/` e `session-end/steps/` — os arquivos novos que o `~/.claude` ainda não tem
porque **o install não rodou**. Isso é a divergência esperada, não defeito: cai quando
`./install.sh --skills` rodar. Releia a lista antes de tratar número diferente como bug do script.
