# Decision log (ADRs)

**Append-only.** Never edit or delete an entry. If a decision is reversed, append a new
entry that supersedes it and add `- Superseded by: D-NNN` to the old one (that one-line
addition is the only permitted edit to a past entry).

Every entry uses this format:

```
## D-NNN · <short imperative title>
- Date:        YYYY-MM-DD
- Session:     S-NNN
- Status:      ACCEPTED | SUPERSEDED(D-NNN) | REVERTED(D-NNN)
- Context:     What forced a choice. What was true at the time.
- Options:     The alternatives actually considered, one line each.
- Decision:    What we did, and why this one.
- Consequences: What this makes easy, what it makes hard, what it locks in.
- Revisit if:  The condition under which a future session should reopen this.
```

Write an ADR when a future session could reasonably reverse your call and would waste
time re-deriving why. Do not write one for routine implementation choices.

---

## D-001 · Adopt the multi-session agent program as the working method
- Date:        2026-07-27
- Session:     S-001
- Status:      ACCEPTED
- Context:     Prism Rush is feature-rich (v1.6, 95 Swift files, ~22.3k lines) and has been
               built across many ad-hoc sessions. `state.md` had grown to 58k and README to
               35k; both mix history, spec, and status, so no single file answers "what is
               true right now and what is next." The owner supplied a written program
               (Phase A scaffold → 7 adversarial audits → triage → execution) plus an
               operating-rules file.
- Options:     (a) Keep working ad hoc from `state.md`.
               (b) Adopt the program as written.
               (c) Adopt a lighter variant — skip the audits, go straight to a backlog.
- Decision:    (b), as written. The audit phase is the point: seven independent lenses in
               seven separate contexts produce genuinely different findings, where one
               context produces one finding restated seven times.
- Consequences: `docs/agent/` becomes the memory of record. `state.md` and `README.md`
               remain the project's human-facing history and are NOT the agent's source of
               truth — where they disagree with `02_STATE.md`, `02_STATE.md` wins and gets
               fixed. Eight sessions elapse before any code changes. In exchange, every
               later session starts from a map instead of a re-exploration.
- Revisit if:  Two consecutive audits produce fewer than five real findings each — at that
               point the remaining audit budget is better spent executing.

## D-002 · Write the charter from repo evidence rather than blocking on Rayan
- Date:        2026-07-27
- Session:     S-001
- Status:      ACCEPTED
- Context:     `PERSONAS.md` step 5 says to ask Rayan the charter questions first. The
               workspace `CLAUDE.md` states AUTONOMOUS MODE: never ask clarifying questions;
               make the best decision available and document it. These conflict directly,
               and this session runs non-interactively.
- Options:     (a) Block the session until answered.
               (b) Write the charter from the strongest available evidence — the six owner
                   decrees already recorded verbatim in the repo `CLAUDE.md`, plus
                   `README.md`, `state.md`, `Store/metadata.md`, `docs/SHIP_CHECKLIST.md` —
                   and mark every inference as an assumption.
               (c) Ship a stub charter.
- Decision:    (b). The owner decrees in `CLAUDE.md` are labelled "verbatim product law" and
               are a stronger source than answers reconstructed in a fresh conversation.
- Consequences: `00_CHARTER.md` carries an explicit **Assumptions** section. Every line in it
               is falsifiable by Rayan in one reading pass. The open questions are carried in
               `HANDOFF.md` until answered.
- Revisit if:  Rayan answers the charter questions — then rewrite `00_CHARTER.md` and mark
               the assumptions resolved.
