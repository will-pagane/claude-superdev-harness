# Measures Jev skill routing on Will's real skill catalog, with Portuguese requests.
# Two gaps at once: the video's "level 1 skill routing" claim, and the never-measured
# Portuguese question. Ground truth = paraphrased requests, never copied from descriptions.
import json, os, time, urllib.request, statistics, sys

KEY = os.environ["TYPESAFE_API_KEY"]
HERE = os.path.dirname(os.path.abspath(__file__))
SKILLS = json.load(open(os.path.join(HERE, "skills.json"), encoding="utf-8"))
NONE = "__nenhuma__"

CASES = [
    ("preciso montar os slides do workshop de quinta", ["brainiac-create-presentation"]),
    ("acabei a call com o Rivan, tenho a gravacao do Fathom aqui", ["col-process-meeting"]),
    ("amanha tenho reuniao com a Brinkanto, me ajuda a chegar preparado", ["col-prepare-meeting"]),
    ("monta um orcamento pro pessoal da Ancora", ["novarc-proposta"]),
    ("quero fechar a sessao e jogar o que a gente decidiu no vault", ["col-session-sync"]),
    ("da um push do que mudou aqui no repositorio", ["brainiac-sync"]),
    ("bora planejar meu dia", ["brainiac-daily-brief"]),
    ("tive um encontro com o mentorado ontem, tenho o audio", ["brainiac-process-mentoria"]),
    ("transforma aquele deck em PNG transparente", ["brainiac-render-presentation"]),
    ("preciso das cores e da tipografia da NOVARC pra uma landing", ["novarc-design"]),
    ("rasga minha palestra antes de eu subir no palco", ["brainiac-talk-review"]),
    ("quero gravar uma aula sobre marketplace, me ajuda com o roteiro", ["brainiac-create-lesson"]),
    ("tira o design system dessas imagens de referencia", ["brainiac-extract-design-system"]),
    ("o vault ta desatualizado, roda uma varredura e me atualiza", ["brainiac-context-maintenance"]),
    ("pergunta pro Hermes como ta a fila dele", ["hermes-ask"]),
    ("checa se a VPS ta de pe", ["hermes-vps"]),
    ("passa esse plano pro Codex rasgar antes de eu codar", ["codex-review", "grill-me-codex"]),
    ("quero entender a arquitetura desse repositorio inteiro", ["graphify"]),
    ("faz uma auditoria completa do codigo do admin", ["code-ultragraph-review", "code-ultragraph-jeview", "code-review"]),
    ("me passa um prompt pra eu continuar isso em outra sessao", ["session-handoff"]),
    ("roda essa checagem de 10 em 10 minutos", ["loop", "schedule"]),
    ("busca na web artigos sobre precificacao de software", ["firecrawl", "firecrawl-search", "firecrawl-deep-research"]),
    ("me monta um site de vendas pra NOVARC", ["site-strategy-copy", "site-page-architecture", "scroll-craft", "site-ship"]),
    ("qual o CNPJ da NOVARC mesmo?", [NONE]),
    ("quanto e 17 vezes 23?", [NONE]),
    ("me explica o que e prompt caching", [NONE]),
]

criteria = {s["name"]: s["description"] for s in SKILLS}
criteria[NONE] = ("No skill covers this request: a plain factual question, arithmetic, a "
                  "conceptual explanation, or anything answered directly without a workflow.")


def ask(pedido):
    body = {
        "state": {"pedido_do_usuario": pedido},
        "model": "jev-latest",
        "questions": {
            "skill": {
                "type": "choice",
                "instructions": {
                    "question": "The state holds one request written in Brazilian Portuguese by "
                                "the owner of this workspace. Which skill should the coding agent "
                                "load to serve it?",
                },
                "criteria": criteria,
            }
        },
    }
    raw = json.dumps(body).encode()
    req = urllib.request.Request(
        "https://api.typesafe.ai/v1/systemone", data=raw,
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.load(r)
    return resp, (time.time() - t0) * 1000, len(raw)


rows, lat, hits = [], [], 0
for pedido, ok in CASES:
    resp, ms, nbytes = ask(pedido)
    a = resp["answers"]["skill"]
    got, conf = a["choice"], a.get("confidence")
    good = got in ok
    hits += good
    lat.append(ms)
    rows.append({"pedido": pedido, "esperado": ok, "jev": got, "conf": conf,
                 "acerto": good, "ms": round(ms), "usage": resp.get("usage"),
                 "model": resp.get("model")})
    print(f"{'OK ' if good else 'ERR'} {round(ms):5}ms conf={conf} {got:35} <- {pedido[:45]}")

tok = sum((r["usage"] or {}).get("input_tokens", 0) for r in rows)
print(f"\nacertos {hits}/{len(CASES)}  p50={round(statistics.median(lat))}ms  "
      f"p95={round(sorted(lat)[int(len(lat)*0.95)-1])}ms  input_tokens={tok}  "
      f"custo=US${tok*0.042/1e6:.6f}  model={rows[0]['model']}")
json.dump(rows, open(os.path.join(HERE, "jev_skill_route_results.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
