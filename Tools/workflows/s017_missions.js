export const meta = {
  name: 's016-missions-pass-017',
  description: 'Deep investigation of the Prism Rush missions surface so pass 017 has a real plan, not a guess',
  phases: [
    { title: 'Investigate', detail: 'seven parallel investigations across the missions surface' },
    { title: 'Verify', detail: 'adversarial refutation of the four load-bearing ones' },
  ],
}

const REPO = '/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios'

const CONTEXT = `
You are an investigator preparing **pass 017 of the Prism Rush program**: a complete rebuild of the
MISSIONS surface. Repo root: ${REPO} (branch main, HEAD ba9655d, working tree clean).

Swift 6 / SwiftUI / RealityKit iPhone endless runner, no third-party dependencies.

## The owner's complaint, verbatim (2026-08-03)

> add into memory that we need a dedicated session to redo the mission section of the app. its ugly.
> does nothing. its not easy to understand. not rewarding at all. need a million review bots. judge,
> think , test implement

**Those are FOUR different defects and they do not have the same fix:**
 - **ugly** — visual craft
 - **does nothing** — missions do not visibly affect anything the player cares about
 - **not easy to understand** — you cannot tell what a mission asks or how far along you are
 - **not rewarding at all** — the payout is not worth the work. **This is an ECONOMY problem, not a
   UI one**, and it is the one most likely to be mis-fixed as a prettier screen.

## Essential context you must not re-derive

Read these before starting:
 - \`${REPO}/CLAUDE.md\` — architecture, the six owner decrees, the nine iron rules.
 - \`${REPO}/docs/agent/audits/scratch/s016_mandate.md\` — the wider owner mandate this sits inside.
 - \`${REPO}/docs/agent/audits/scratch/s016_coins-economy.md\` — S-016 mapped the whole economy:
   every coin source and sink, grind times, the Mystery Box, and a three-column sort of proposed
   monetization mechanics against decree 5. **The missions reward curve has to be costed against
   that, not invented fresh.**
 - \`${REPO}/docs/agent/audits/scratch/s016_design-system.md\` — the current visual system with every
   colour, the type scale, and ten ranked craft findings (F1-F10). §5 is a before/after spec format
   worth copying.

**Owner rulings already made (D-050), which constrain you:**
 - All three flagged monetization mechanics ship (near-miss reveals, real countdown offers,
   post-death starter bundle) — but **decree 5 is NOT revoked**: advertised bonuses are always
   delivered and there is no fake urgency, so a countdown must be real and enforced in code.
 - Buying a deep world with coins keeps forfeiting leaderboard/reach/achievements.
 - "Zero binary assets" IS revoked (D-046) — real art, textures and models are allowed now, subject
   to a memory budget and an AI-generated/CC0-only licensing floor.

**Iron rules that still bind:** Core/ never imports a renderer or UIKit; all randomness through the
seeded SplitMix64 (a seed fully determines a run — no \`Double.random\`, no \`Date()\` in Core/); any
spawn-path/RNG change bumps \`DailyChallenge.layoutVersion\` and re-runs the solvability bot;
\`Profile\` fields are always \`decodeIfPresent ?? default\` (old saves must never wipe); never \`@State\`
a shared \`@Observable\`; Swift 6 strict concurrency \`complete\`; **never make a gate pass by weakening
it** (deleting an assertion, widening a band, skipping a test).

## Output contract — THE ONLY THING THAT SURVIVES

Write to \`${REPO}/docs/agent/audits/scratch/s017_<LABEL>.md\` BEFORE you return. Anything you found
and did not write there is destroyed when the workflow ends.

Every claim carries an exact \`file:line\`. If you looked and it is not there, say "NOT FOUND" and
give the grep you ran. READ-ONLY — edit nothing but your own output file, do not build, do not run
simctl. Your return text is a <= 25 line executive summary; the FILE carries the detail.
`

const DIMENSIONS = [
  {
    label: 'missions-inventory',
    verify: true,
    prompt: `LABEL = missions-inventory.

Establish exactly what the missions system IS today. Everything else depends on this being right.

Read in full: \`PrismRush/Meta/MissionCatalog.swift\`, \`PrismRush/UI/MissionsView.swift\`,
\`PrismRush/Meta/Profile.swift\` (the mission-related fields), \`PrismRush/Meta/ProfileStore.swift\`
(mission progress, claiming, rolling), and every test in \`Tests/\` that touches missions.

Deliver:
 1. **Every mission type**, with: its id, its display text, its trigger condition, its target value,
    its reward, its cadence (daily/weekly/challenge), and the exact code that advances it. A full
    table. If some are unreachable or can never complete, say so — that is a headline finding.
 2. **The complete lifecycle**: when are missions rolled, from what source of randomness, when do
    they reset, what happens to an unclaimed mission at reset, and can progress be lost. Quote the
    roll and reset code. **If the roll uses \`Date()\` or an unseeded RNG, say so** — that is fine
    outside Core/ but it changes what is testable.
 3. **The claim path**: what happens on CLAIM and CLAIM ALL, where the reward is credited, whether it
    is idempotent, and whether the profile is mutated from inside a SwiftUI \`body\` (the repo has a
    filed defect saying it is — verify at file:line).
 4. **What already exists that the owner may not have seen**: any mission board summary, badges,
    progress rings, streaks. The hub nav shows a "3" badge on MISSIONS — find what feeds it.
 5. **Known filed defects.** Search \`docs/agent/03_BACKLOG.md\` for every mission item (PR-0304 is
    "ALL CLEAR on a 0/N board at first launch"; there are mission-claim items too). List them with
    their current status, and mark which are still real against today's code.
 6. **Test coverage**: what is actually tested, and what is structurally untestable because
    \`swift test\` compiles none of \`UI/\`.`,
  },
  {
    label: 'missions-does-nothing',
    verify: true,
    prompt: `LABEL = missions-does-nothing.

**"does nothing" is the owner's second complaint and it is the most interesting one.** Your job is to
find out whether missions actually affect anything the player cares about, and if they do, why that
is invisible.

Trace, with file:line, the full consequence chain of completing a mission:
 1. What does a mission reward actually pay? Coins, XP, gems, a skin, nothing? Quote the reward
    table and the crediting code.
 2. Where does that reward land, and **does the player ever see it land**? Is there a burst, a toast,
    a number that moves? (Note: S-016 shipped \`RewardBurstView\` for the daily bonus and free chest —
    \`PrismRush/UI/RewardBurstView.swift\`, decision D-049. Missions do NOT use it. Say whether they
    should, and what the seam would be.)
 3. Do missions feed anything else — XP/levels, achievements, streaks, Game Center, character
    unlocks, world unlocks? Follow each thread and rule on it.
 4. **The killer question: if a player never opened the missions screen, what would they lose?**
    Quantify it — coins per day, XP per day, as a fraction of total earn rate. Cost it against the
    economy map in \`s016_coins-economy.md\`. If the answer is "almost nothing", that IS the defect
    and everything else is cosmetic.
 5. Is there any mission whose completion changes how the GAME plays (a new pattern, a modifier, a
    world, a character)? Or are they all pure payout? Ruling.
 6. Compare against what the repo's own design bible says missions are for —
    \`docs/agent/05_GAME_DESIGN.md\`. Quote the relevant section. If the shipped system does not do
    what the bible says, that gap is the plan's spine.`,
  },
  {
    label: 'missions-economy',
    verify: true,
    prompt: `LABEL = missions-economy.

**"not rewarding at all" — the complaint most likely to be mis-fixed as a prettier screen.** This is
an economy brief. Bring numbers.

Read \`s016_coins-economy.md\` FIRST (it maps every coin source and sink with grind times) and build
on it rather than redoing it. Then:
 1. **What a mission pays, per mission and per day**, across daily/weekly/challenge. Exact numbers
    from \`MissionCatalog.swift\`.
 2. **What that is worth as a fraction of everything.** How many coins does a typical run pay? A good
    run? So: completing every mission every day is worth how many runs of grinding? Express the
    mission layer as a percentage of daily earn. **If it is under ~15% the owner is objectively
    right and the fix is numeric, not visual.**
 3. **What it buys.** Against the real sinks — characters, deep worlds (13,400 coins each), power-up
    packs, the Mystery Box (300) — how many days of perfect mission completion buys each? Table.
 4. **The effort/reward curve.** For each mission, estimate the effort (runs required, or is it
    passive?) against the payout. Find the missions that are actively insulting — high effort, low
    pay — and the ones that pay for doing nothing. Both are defects.
 5. **Propose a corrected reward curve** with real numbers, and show the daily/weekly earn it
    implies. State explicitly what it does to time-to-purchase for each sink, because inflating
    mission rewards devalues the coin IAPs — that trade is the owner's to make, so give him the
    numbers, not a recommendation dressed as a fact.
 6. **Decree 5 check.** Decree 5 stands: advertised bonuses always delivered, no fake urgency. If any
    proposed mechanic (streak pressure, expiring missions, "come back in 2h") straddles it, sort it
    into ship / owner-must-rule / needs-a-revocation exactly as \`s016_coins-economy.md\` did.
 7. Reference how 2-3 shipped mobile games structure mission/quest rewards as a fraction of earn.
    Use web research and cite it.`,
  },
  {
    label: 'missions-craft',
    verify: false,
    prompt: `LABEL = missions-craft.

**"its ugly" and "its not easy to understand"** — the visual and information-architecture half.

Read \`PrismRush/UI/MissionsView.swift\` in full, plus \`PrismRush/UI/Theme.swift\` and whatever shared
components it uses (\`MetaScreenScaffold\`, cards, progress bars). Cross-reference
\`s016_design-system.md\`'s findings F1-F10 — several of them (gold means six things, one-gradient-
per-screen violations, generic SF Symbols where bespoke glyphs exist) may land on this screen too.

Deliver:
 1. **A precise description of the current screen**, structured enough to redraw without opening the
    code: every row, its height, its colours with hexes, its type sizes, its states (locked, in
    progress, complete, claimed, expired). Include the empty state and the all-complete state.
 2. **Why it is hard to understand.** Be specific and mechanical: is the target value shown? Is
    progress a number, a bar, both, neither? Can you tell a daily from a weekly at a glance? Is the
    reward visible before you complete it? Is the reset time shown? Each of those is a yes/no with a
    file:line.
 3. **Every craft defect**, ranked, with file:line. Apply the repo's own decrees: decree 6 (clarity
    beats spectacle, role-based colour, one gradient family per screen), decree 3 (no broken-looking
    states for expected situations — check the 0/N first-launch board, PR-0304), decree 4
    (everything on screen leads somewhere).
 4. **A BEFORE/AFTER spec** in the format of \`s016_design-system.md\` §5 — an ASCII wireframe of the
    current screen and of the proposed one at 402x874 pt, with exact colours and sizes, drawable
    without reading code again. This section is the deliverable the next session builds from.
 5. Reference at least three shipped games' quest/mission screens and name specifically what to take
    from each. Use web research.
 6. Say which of the repo's existing components can be reused (the reward burst, progress rings,
    neon cards) so the rebuild is a revision, not a second design language.`,
  },
  {
    label: 'missions-seam',
    verify: false,
    prompt: `LABEL = missions-seam.

The implementation brief: exactly where the code has to change, and what will break.

 1. **Map the architecture** of the missions feature end to end: catalog → profile storage → progress
    advancement → UI → claim → reward. One diagram in text, then a table of every file:line that
    participates.
 2. **Where does mission progress get advanced from?** Find every call site. Is it driven from
    \`GameCore\` (which must stay renderer-free and deterministic), from \`GameView\`, or from
    \`ProfileStore\`? If any mission condition reads game state per-frame, say so — that is a perf
    exposure and S-016 just fixed a related one (D-051: the sim ran at full rate behind meta sheets
    because \`GameCore.snapshot\` is the only observed property on an \`@Observable\`).
 3. **The \`Profile\` migration question.** Any new mission field must be
    \`decodeIfPresent ?? default\` (iron rule 7). List the existing mission fields and their defaults,
    and state exactly what a new field would need so an old save never wipes. Quote \`init(from:)\`.
 4. **Determinism.** Do missions touch the seeded RNG or the spawn path in any way? If a proposed
    mission type would (e.g. "collect N gems in one run" is fine; "spawn a special pickup" is not),
    flag which proposals cost a \`layoutVersion\` bump and a solvability-bot re-run.
 5. **The G3 anti-pattern.** The repo forbids \`@State\`-ing a shared \`@Observable\` and snapshotting
    \`store.profile\` into a \`let\` at the top of \`body\`. Audit \`MissionsView.swift\` for both and
    report at file:line — the repo has a filed defect saying mission claiming mutates and persists
    the profile from inside \`body\`.
 6. **What tests exist, what tests should exist**, and which of them can run under \`swift test\`
    (which compiles only Core/, seven Meta/ files and Audio/Synth.swift — NOT UI/). Propose the
    specific tests pass 017 should ship, favouring ones that live in the testable layer.
 7. **Risk register**: rank what could go wrong in this rebuild, worst first.`,
  },
  {
    label: 'missions-references',
    verify: false,
    agentType: 'general-purpose',
    prompt: `LABEL = missions-references.

Research how shipped mobile games actually structure missions/quests, so pass 017's plan is grounded
rather than invented. Use web search and fetch extensively; cite every source with a URL.

The owner has separately said "ciopy subway surfers" about the wider game, so cover it first — but
**we copy structure and pacing, never art, names or trademarks. Say so explicitly in your output.**

Cover, with specifics and numbers where findable:
 1. **Subway Surfers**: daily challenges, the word hunt, the mission/star system, season passes. How
    many missions are active at once? How are they surfaced — a screen you visit, or inline on the
    main menu? What do they pay relative to a run? What happens when you complete a set?
 2. **Two or three other high-retention runners or casual games** (Temple Run, Alto's Odyssey, Crossy
    Road, Candy Crush's quest system) for contrast. Where do they put missions in the UI hierarchy?
 3. **The patterns worth stealing**, specifically:
    - How is progress shown so it is legible in under a second?
    - How do they make a mission feel worth doing — reward size, streak/set completion, or unlocks?
    - How do they handle the empty/first-launch state?
    - Do missions ever change how the game PLAYS, or are they always payout?
    - How is the reset/expiry communicated without manufacturing fake urgency?
 4. **Anti-patterns to avoid** — the mission designs players complain about, and why.
 5. A synthesis: a ranked list of what Prism Rush should take, each with (a) what the reference does,
    (b) what Prism Rush does today, (c) the specific change, (d) rough cost.`,
  },
  {
    label: 'missions-plan',
    verify: false,
    prompt: `LABEL = missions-plan.

You write LAST in spirit but run in parallel, so build the **plan skeleton** the other six fill in.
Your job is the shape of pass 017, its sequencing, and its verification — not the findings.

Read \`docs/agent/01_RULES.md\` (how this program works), \`docs/agent/02_STATE.md\`, and
\`docs/agent/sessions/SESSION_015.md\` as an example of what a good session log looks like.

Deliver:
 1. **A step-by-step plan for pass 017**, ordered so the app builds and is shippable at every step.
    Each step: what changes, which files, how it is verified, and what it depends on. Assume the
    session has one goal and must finish it.
 2. **The sequencing argument.** The four complaints (ugly / does nothing / unclear / unrewarding)
    are not equally hard and not independent. Which must be fixed first for the others to matter?
    Make the case. My prior, attack it: **"does nothing" and "not rewarding" are the same root
    problem and must be fixed before any pixel moves**, because a beautiful screen for a system that
    pays nothing is still a screen nobody opens.
 3. **The verification plan.** This program's hard rule is: run the app before claiming anything
    works, and paste real command output into the session log. \`swift test\` does NOT compile UI/.
    Specify exactly how each step gets verified — which are unit-testable, which need a simulator
    capture, which need the owner's eyes. Name the screenshots that must be taken.
 4. **What the owner must decide** before or during the pass, as specific answerable questions. The
    reward curve is his call (it trades against coin IAP revenue). Anything touching decree 5 is his.
 5. **A scope fence.** Name what pass 017 explicitly does NOT do, so it does not sprawl. Note that
    pass 018 is the character preview seam + asset pipeline and 019 is the new character art —
    missions must not start eating those.
 6. **The rollback story.** What is the recovery tag, what is the largest irreversible step, and how
    would a future session undo this if the owner hates it.`,
  },
]

phase('Investigate')

const results = await pipeline(
  DIMENSIONS,
  (d) => agent(`${CONTEXT}\n\n---\n\n${d.prompt}`, {
    label: `dig:${d.label}`,
    phase: 'Investigate',
    ...(d.agentType ? { agentType: d.agentType } : {}),
  }).then((text) => ({ ...d, text })),
  (r) => {
    if (!r || !r.verify) return r
    return agent(
      `You are a HOSTILE verifier for the Prism Rush program. Repo root: ${REPO} (HEAD ba9655d,
clean tree). READ-ONLY — edit nothing but your output file. No builds, no simctl.

An investigator produced \`${REPO}/docs/agent/audits/scratch/s017_${r.label}.md\`. READ IT.

**Your job is to REFUTE it.** Session 003 of this program raised 124 findings and killed 32 with
hostile readers. Default to "refuted" when uncertain. Agreeing is worthless.

 1. Open EVERY file:line cited. Confirm the code is verbatim and at that line. The tree is clean, so
    a wrong line number is a real error.
 2. Re-derive every number independently with python3 — do not check their arithmetic, redo it. This
    matters most for the economy claims: coins per run, per day, time-to-purchase.
 3. Find the simpler explanation they missed and the case their proposal does not handle. Walk edge
    cases: a brand-new profile, a profile that has not opened the app in a week, an unclaimed
    mission at reset, a mission completed on the death frame, clock rollback.
 4. **Check every proposal against the decrees and iron rules** and name any it violates: Core/ never
    imports a renderer; a seed fully determines a run; spawn-path changes bump
    \`DailyChallenge.layoutVersion\` and re-run the solvability bot; \`Profile\` fields decode as
    \`decodeIfPresent ?? default\`; never \`@State\` a shared \`@Observable\`; Swift 6 strict concurrency;
    decree 3 (no broken-looking states for normal situations); decree 5 (no dark patterns, no fake
    urgency, advertised bonuses always delivered); decree 6 (clarity beats spectacle).
    Note "zero binary assets" was REVOKED (D-046) and is no longer a valid objection.
 5. **Catch anything that would make an existing gate pass by weakening it** — a deleted assertion, a
    widened band, a skipped test. Most valuable catch available.
 6. If it proposes shipping third-party art, names or trademarks, flag it hard.

Write to \`${REPO}/docs/agent/audits/scratch/s017_verify_${r.label}.md\` BEFORE returning. Open with
CONFIRMED / PARTIALLY REFUTED / REFUTED, then what survives, what is refuted with your own
derivation, what is missing, and a corrected version of anything you refuted. Return <= 20 lines.`,
      { label: `verify:${r.label}`, phase: 'Verify' }
    ).then((v) => ({ ...r, verdict: v }))
  }
)

const done = results.filter(Boolean)
log(`${done.length}/${DIMENSIONS.length} missions investigations complete`)

return {
  investigated: done.map(d => d.label),
  verified: done.filter(d => d.verdict).map(d => d.label),
  summaries: done.map(d => ({ label: d.label, summary: d.text, verdict: d.verdict ?? null })),
}
