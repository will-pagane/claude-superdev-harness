# Jev measurement log — 2026-09-22: skill routing, in Portuguese

One experiment, run to answer two open items at once:

- the "level 1 skill routing" claim in the two Jev videos Will brought on 2026-09-22;
- the gap this project declared on 2026-09-21 — *"nenhuma medição foi em português"*.

Raw evidence: `skill-routing-ptbr-20260922/` (`jev_skill_route.py`, `jev_skill_route_results.json`,
`skills.json`). Verdict and context in the vault:
`knowledge/ferramentas/jev-onde-um-modelo-de-decisao-cabe.md`.

## Design

One `choice` per request. `criteria` is the real skill catalog read off disk — 68 `SKILL.md`
frontmatters from `.claude/skills` (vault) and `~/.claude/skills` — plus a `__nenhuma__` option.
`state` carries one request and nothing else.

26 requests, written the way Will writes, **paraphrased on purpose and never copied from any
`description`**. One request per call, because that is the real shape: one routing decision per
turn.

**Stated premises.** Descriptions truncated to 400 characters. The catalog is what exists on
disk, so harness-owned skills (`loop`, `schedule`, `code-review`) are absent — this session's
listing carries 118 skills, disk carries 68. `jev-latest` resolved to `jev-1.13.0`.

## Result

| | |
|---|---|
| correct | **24/26 raw; 25/26 discounting one case whose answer was not in the catalog** |
| latency | p50 **906 ms**, p95 975 ms |
| cost | US$ 0,0068 for all 26 (161 005 input tokens) |
| confidence on the correct answers | 0,60 – 1,00 |

Confidence gate sweep:

| gate | routed | correct among routed |
|---|---|---|
| 0,50 | 25/26 | 24/25 |
| 0,60 | 25/26 | 24/25 |
| 0,70 | 21/26 | **21/21** |

## The two misses, which matter more than the 24 hits

**`"roda essa checagem de 10 em 10 minutos"` → `firecrawl-monitor` (conf 0,66).** The right
answers, `loop` and `schedule`, are harness skills and are **not on disk**, so they were never
offered. Two defects, not one:

1. *Catalog coverage.* Any S7 implementation that reads only `~/.claude/skills` and
   `.claude/skills` inherits this hole. The real listing is 118 skills; disk gave 68.
2. *No-match design.* `__nenhuma__` was described only as "a plain factual question, arithmetic,
   a conceptual explanation". It did not cover *"a skill exists for this, but it is not in this
   list"*. The model cannot abstain into a case nobody described.

**`"qual o CNPJ da NOVARC mesmo?"` → `firecrawl-search` (conf 0,44).** The only genuine error, and
it carries the lowest confidence of all 26. A gate at 0,5 already sends it to passthrough.

## Verdict on Portuguese

It did not degrade. 24/26 here against 12/12 and 27/27 in English on 2026-09-21, with both misses
explained by catalog coverage and by low confidence rather than by language. The model card's
caveat still stands for long, ambiguous prose; for a **short request against a closed taxonomy**,
Will's Portuguese passed, and that shape can join the auto-fire list.

Still unmeasured: long Portuguese prose (transcripts, meeting records, email) and volume
classification over Will's own content.
