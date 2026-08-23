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
