# Algorithm Upgrade Analysis

**Scope.** Two questions, answered against the code as it exists today:

1. What spaced-repetition / memory algorithms exist beyond the four the app
   ships (`SchedulerKind.circles`, `.leitner`, `.sm2`, `.fsrs`), and which of
   them are worth adding?
2. If the app upgrades input complexity beyond the binary
   I Know / I Don't Know answer, what UI and logic changes are needed?

**Status:** analysis only — no code changes are proposed here as diffs; every
recommendation names the concrete types/files that would change.

---

## 0. Ground truth: what the app has today

Everything below is grounded in these files:

| Concern | Where |
| --- | --- |
| Scheduler protocol + 4 implementations | `Packages/VocabKit/Sources/VocabKit/Scheduler.swift` |
| Legacy circles path + `isDue` | `Packages/VocabKit/Sources/VocabKit/SRS.swift` |
| Session building, answer flow, requeue | `Packages/VocabKit/Sources/VocabKit/StudyEngine.swift` |
| Per-word state (`WordState`) | `Packages/VocabKit/Sources/VocabKit/Models.swift` |
| Persistence + review log | `Packages/VocabKit/Sources/VocabKit/UserStore.swift` |
| Settings (`AppSettings.scheduler`) | `Packages/VocabKit/Sources/VocabKit/AppSettings.swift` |
| Shared view model (`StudyModel.answer(_:)`) | `Apps/Shared/PageModels.swift` |
| Flashcard UI (both frontends) | `Apps/Redesign/NeoStudyViews.swift`, `Apps/Classic/StudyViews.swift` |

Key facts that constrain any upgrade:

- **The input is binary by contract.** `Scheduler.apply(answer knew: Bool, to:now:calendar:)`
  is the single entry point; `StudyEngine.answer(_:session:state:scheduler:now:)`
  and `StudyModel.answer(_ knew: Bool)` pass a `Bool` all the way from the two
  buttons in `NeoFlashcardView.bottomControls`
  (`study.know` / `study.dontKnow` accessibility identifiers).
- **Binary answers are already being *coerced* into graded algorithms.**
  `SM2Scheduler` maps know → q=4, forgot → q=2. `FSRSScheduler` maps
  know → Good (3), forgot → Again (1). Notably, the FSRS-4.5 weight array
  `FSRSScheduler.w` already contains all 17 weights **including `w[15] = 0.2272`
  (Hard penalty) and `w[16] = 2.8755` (Easy bonus), which are currently dead
  weight** — they are only ever used by ratings 2 and 4, which the binary UI can
  never produce. The stability math for Hard/Easy is one multiplication away.
- **A full review log already exists.** `UserStore.logStudy(word:knew:wasNew:at:)`
  appends to the `study_log` table (`word, studied_at, knew, was_new`). This is
  exactly the raw material an FSRS parameter optimizer needs (grade granularity
  aside — see §2.5), and elapsed intervals are reconstructible from consecutive
  `studied_at` timestamps per word.
- **Schema migration is cheap and already has a pattern.** `UserStore.migrate()`
  adds columns with a tolerant
  `for column in [...] { _ = try? db.execute("ALTER TABLE ... ADD COLUMN ...") }`
  loop (used for `interval_days`, `ease_factor`, `stability`, `difficulty`).
  New columns follow the same pattern with zero migration risk.
- **Scheduling granularity is whole days.** `Scheduler.schedule(_:days:now:calendar:)`
  clamps to `[1, 730]` days and anchors to `startOfDay`. Sub-day intervals do
  not exist; same-day repeats happen only through the in-session requeue in
  `StudyEngine.answer` (failure re-inserts the card ~3+ positions ahead).
  Note a subtlety: when that requeued card is answered again the same session,
  `FSRSScheduler` sees `elapsed ≈ 0`, so retrievability ≈ 1 and the success
  growth term `e^{w10·(1−R)} − 1 ≈ 0` — same-day successes barely move
  stability. FSRS-6/7 model same-day ("short-term") reviews explicitly, which
  is directly relevant to this app's requeue behavior (§1.2).
- **User-freedom principles** (from `docs/ALGORITHMS.md` and the
  `SchedulerKind` doc comment): the algorithm is a Settings choice; every
  algorithm consumes the same input; switching never invalidates progress;
  unused `WordState` fields are carried along; manual familiarity edits are
  always respected. Any upgrade must preserve all five.
- **Answer-before-reveal is supported.** `NeoFlashcardView.answerTapped(_:)`
  stores a `pendingAnswer` when the card isn't revealed, reveals, and commits
  on the second tap. Any richer input design must decide what happens to this
  fast path (§2.3, design F).

---

## Part 1 — The algorithm landscape beyond the current four

### 1.1 How to judge candidates: the benchmark baseline

The [open-spaced-repetition srs-benchmark](https://github.com/open-spaced-repetition/srs-benchmark)
evaluates 30+ algorithms on ~10,000 Anki users / ~700M reviews, using log loss,
RMSE(bins), and AUC on predicted recall probability. Selected results
(log loss, lower is better; "without same-day reviews" table; per-user
optimized unless noted):

| Algorithm | Log loss | RMSE(bins) | Params | Note |
| --- | --- | --- | --- | --- |
| RWKV-P (neural) | 0.2773 | 0.0250 | 2.76M | best overall; population-trained |
| LSTM (neural) | 0.3332 | 0.0538 | 8,869 | per-user fine-tuned |
| GRU (neural) | 0.3333 | 0.0556 | 503 | |
| FSRS-7 | 0.3437 | 0.0655 | 35 | current SOTA among "small" models |
| FSRS-6 | 0.3460 | 0.0653 | 21 | |
| FSRS-4.5 (optimized) | 0.3624 | 0.0764 | 17 | *what the app implements, minus optimization* |
| FSRS-7 **default params** | 0.3629 | — | 0 trained | ≈ ties *optimized* FSRS-4.5 |
| DASH | 0.3682 | 0.0836 | 9 | logistic regression |
| DASH[MCM] | 0.3688 | 0.0861 | 9 | |
| DASH[ACT-R] | 0.3728 | 0.0886 | 5 | |
| AVG (dumb baseline) | 0.3945 | 0.1034 | 0 | "an algorithm that doesn't outperform AVG cannot be considered good" |
| ACT-R | 0.4033 | 0.1074 | 5 | below baseline |
| HLR (Duolingo) | 0.4694 | 0.1275 | 3 | below baseline |
| Ebisu v2 | 0.4989 | 0.1627 | 0 | below baseline |
| SM-2 | (bottom of table) | — | 0 | worst tier alongside its Anki variant |

Two headline conclusions frame everything else:

1. **The DSR family (FSRS) dominates every classical alternative** at any
   comparable complexity. Nothing between SM-2 and FSRS (Leitner variants,
   HLR, ACT-R, DASH, Ebisu) beats even un-optimized modern FSRS.
2. **A newer FSRS with default weights ≈ an older FSRS with per-user
   optimization.** FSRS-7-default (0.3629) statistically ties optimized
   FSRS-4.5 (0.3624). For this app — which ships FSRS-4.5 defaults — the
   cheapest large win is *upgrading the model version*, not building an
   optimizer.

### 1.2 Candidate-by-candidate survey

Grading key — **Data**: per-review inputs required. **On-device**: can it run
fully in Swift, offline, with no server or training pipeline. **Cost**:
S ≈ days, M ≈ 1–2 weeks, L ≈ month+.

#### FSRS-5 / FSRS-6 (full model, default parameters)

- **Mechanism.** Same DSR (Difficulty–Stability–Retrievability) structure the
  app already implements: power-law forgetting curve, stability growth on
  success, collapse on lapse, mean-reverting difficulty. FSRS-5 (19 params)
  adds explicit handling of **same-day reviews** (a short-term stability
  update using elapsed seconds, not days). FSRS-6 (21 params) additionally
  makes the **forgetting-curve decay a learnable/per-deck parameter (w20)**
  instead of the fixed −0.5 hardcoded in `FSRSScheduler.decay`. FSRS-7
  (35 params, 2026) continues the line; its default parameters already match
  optimized FSRS-4.5.
- **Data needed.** Exactly what `WordState` already stores (`stability`,
  `difficulty`, `lastStudiedAt`) plus a rating 1–4; binary maps to 1/3 as today.
- **On-device.** Yes, trivially — pure arithmetic, same shape as the existing
  ~80-line `FSRSScheduler`. There is also
  [open-spaced-repetition/swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs),
  an official Swift package (scheduler only, no optimizer), if a dependency is
  preferred over extending the in-house struct.
- **Benefit.** Meaningful accuracy gain over the shipped FSRS-4.5 for free
  (no new UI, no training), plus *correct handling of the app's own in-session
  requeue*: today a same-session second answer is a modeling blind spot
  (elapsed ≈ 0 ⇒ no stability change); FSRS-6's short-term component fixes
  exactly this case.
- **Cost: S–M.** Update the weight vector, add the same-day branch and the
  w20-parameterized decay; `WordState` needs no new fields. Migration: none —
  existing `stability`/`difficulty` values carry over (the model semantics are
  compatible; at worst intervals shift slightly on next review, which the
  "switching never invalidates progress" principle already tolerates).
- **Verdict: add.** This is the single highest-value algorithm change
  available. It can even replace the current `.fsrs` case in place rather
  than becoming a fifth `SchedulerKind` (the summary string just stops saying
  "4.5").

#### FSRS parameter optimizer (per-user weight training)

- **Mechanism.** Gradient descent (mini-batch Adam) minimizing log loss of
  predicted recall over the user's own review log; produces a personal weight
  vector. Reference implementation is
  [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs) (Rust, with
  optimization); the official Swift package does *not* include it.
- **Data needed.** Full review history per card: rating, elapsed time since
  previous review. The app's `study_log` has timestamps and binary `knew`
  (mappable to Again/Good); §2.5 proposes logging grades + elapsed/scheduled
  days going forward so the optimizer trains on real 4-grade data.
- **On-device.** Feasible but non-trivial. Options: (a) port the training loop
  to pure Swift (the loss and its gradient are closed-form; a few hundred
  lines + Accelerate; run on a background thread; guideline in the FSRS
  ecosystem is ~400–1000 reviews before optimization beats defaults);
  (b) link `fsrs-rs` via a C FFI (adds a Rust toolchain to the build);
  (c) skip it — defensible given the default-vs-optimized finding in §1.1.
- **Benefit.** Roughly the same size of gain as one model-version bump
  (≈ 0.02 log loss), *but only after the user accumulates on the order of a
  thousand reviews*, and much of the gain requires graded (not binary) data.
- **Cost: L** (pure-Swift port incl. testing/convergence hardening) or
  **M–L** (FFI).
- **Verdict: defer to Phase 3.** Do the schema/logging groundwork now (cheap),
  train later. Never block the graded-input work on it.

#### SuperMemo SM-17 / SM-18 (and SM-19)

- **Mechanism.** The original three-component DSR model: per-user matrices for
  recall, stability increase (SInc), and difficulty, updated from the user's
  entire repetition history; retrievability estimated from three information
  sources and reconciled with actual grades. SM-18 changes difficulty to a
  per-repetition, expectation-based estimate. See
  [supermemo.guru/wiki/Algorithm_SM-18](https://supermemo.guru/wiki/Algorithm_SM-18).
- **Data needed.** Full per-item repetition histories plus persistent global
  matrices; 5-grade input.
- **On-device.** Technically yes, but there is **no published reference
  implementation**; the algorithm is proprietary (SuperMemo World), documented
  only as prose. Reimplementation is a research project with no conformance
  test suite.
- **Benefit.** None demonstrated: on SuperMemo's own datasets, FSRS matches or
  beats SM-17-family metrics in the benchmark's universal-metric comparisons,
  with 21 parameters instead of matrices.
- **Cost: L+**, legal ambiguity included.
- **Verdict: reject.** FSRS-6 is the open, better-fit descendant of the same
  theory. Mention in `docs/ALGORITHMS.md` as lineage at most.

#### Duolingo Half-Life Regression (HLR)

- **Mechanism.** Models recall as `p = 2^(−Δt / h)` where the half-life `h` is
  `2^(θ·x)` for a trained weight vector θ over features x (correct/incorrect
  counts, lexeme tags). Trained offline on population-scale logs
  ([Settles & Meeder, ACL 2016](https://research.duolingo.com/papers/settles.acl16.pdf)).
- **Data needed.** Per-review correctness counts *plus a trained θ* — i.e., a
  training pipeline over many users. Duolingo's public release is a research
  artifact, trained on their 13M-session dataset.
- **On-device.** Inference yes (it's a dot product); training no (needs a
  population corpus the app doesn't have; single-user fits are exactly what
  the benchmark shows failing: 0.4694, below the AVG baseline).
- **Benefit.** Negative vs. the shipped FSRS-4.5. HLR was designed for
  Duolingo's implicit, many-exposures-per-session setting, not deliberate
  flashcards.
- **Cost: M** (with nothing to gain).
- **Verdict: reject.**

#### DASH / DASH[MCM] / DASH[ACT-R]

- **Mechanism.** "Difficulty, Ability, Study History": logistic regression on
  time-windowed counts of past attempts/successes, with psychologically
  motivated decay windows (Lindsey, Mozer et al.; extended by
  [DAS3H](https://files.eric.ed.gov/fulltext/ED599174.pdf)). MCM/ACT-R
  variants swap the window kernel.
- **Data needed.** Windowed review counts per item (derivable from
  `study_log`), plus fitting the 5–9 regression weights per user or per
  population.
- **On-device.** Yes; a logistic regression fit is easy in Swift/Accelerate.
- **Benefit.** Benchmarks *slightly worse* than optimized FSRS-4.5
  (0.3682 vs 0.3624) — i.e., worse than what's already shipped, at the price
  of adding a fitting step. Also predicts probability only; turning it into a
  scheduler needs an extra interval-search layer.
- **Cost: M.**
- **Verdict: reject** as a scheduler. (Its windowed-counts idea could someday
  inform a stats screen, nothing more.)

#### ACT-R declarative memory (Pavlik & Anderson)

- **Mechanism.** Memory activation is the log of summed power-law-decaying
  traces of *every* past exposure; recall probability is a logistic function
  of activation; spacing effects emerge because each trace's decay rate
  depends on activation at encoding time.
- **Data needed.** Complete per-item timestamp history at inference time
  (which `study_log` does hold), plus 5 fitted parameters.
- **On-device.** Yes; O(history length) per prediction.
- **Benefit.** 0.4033 — below the AVG baseline in the benchmark. Beautiful
  theory, poor calibration on real flashcard logs.
- **Cost: M.**
- **Verdict: reject** as a scheduler. As with DASH, at most an internal
  curiosity.

#### Ebisu (Bayesian, v2/v3)

- **Mechanism.** Puts a Beta prior on recall probability at a reference
  half-life; exponential decay is handled analytically, and each quiz result
  updates the posterior via moment matching. Three numbers per card (α, β, t).
  v3 replaces the single exponential with an ensemble of power-law-ish decays.
  ([fasiha/ebisu](https://github.com/fasiha/ebisu))
- **Data needed.** Binary (or binomial/noisy-binary) results only — it is the
  *one* candidate designed natively for this app's binary input.
- **On-device.** Yes, delightfully: ~200 lines of pure math, existing Java/
  Dart ports prove portability; a Swift port is a weekend (S).
- **Benefit.** As a *scheduler*, poor: v2 benchmarks worst-in-class (0.4989);
  it has no difficulty dimension and systematically underestimates the spacing
  effect. Its genuine strength is `predictRecall` — a cheap, principled,
  always-current recall probability for *ranking* cards. But the app can get
  the same ranking signal from `FSRSScheduler.retrievability(days:stability:)`,
  which is already `public` and already computed from stored state.
- **Cost: S.**
- **Verdict: reject as a fifth scheduler; steal the idea.** A
  "most at risk first" `StudyOrder` case using the existing FSRS
  retrievability function delivers Ebisu's practical benefit with zero new
  model state.

#### Memrise-style fixed ladder

- **Mechanism.** Fixed interval ladder (≈ 4h, 12h, 24h, 6d, 12d, 48d, 96d,
  180d), advance on success, reset on failure. Structurally identical to
  `CirclesScheduler` with different constants and sub-day early steps.
- **Verdict: reject** — redundant. The app already has two fixed ladders
  (`SRS.intervals` = 1/2/4/7/15/30 and `LeitnerScheduler.boxIntervals` =
  1/2/4/8/16); a third teaches users nothing new. Sub-day steps would also
  break the `schedule()` day-granularity contract for no modeling gain.

#### Neural approaches: GRU-P, LSTM, RWKV, Transformer, KARL, "deep KT"

- **Mechanism.** Recurrent or attention models over the review sequence
  predict next-recall probability; the top of the benchmark table. KARL
  ([arXiv:2402.12291](https://arxiv.org/abs/2402.12291)) additionally embeds
  the *content* of the card with BERT and retrieves similar cards' histories
  (content-aware scheduling).
- **Data needed.** Population-scale training corpora (the benchmark's RWKV is
  trained on 5,000 users); per-user fine-tuning pipelines; for KARL, an
  embedding model at runtime.
- **On-device.** Inference is feasible via Core ML (the GRU is only 503
  params!), but the *training/personalization pipeline* is not, and shipping
  fixed population weights from Anki users to this app's very different
  binary-input population is unvalidated. Interpretability also drops to zero
  — the app currently shows "Memory: Circle N" and interval reasoning users
  can understand; a black box conflicts with the product's
  user-in-charge stance.
- **Benefit.** Best raw accuracy (0.27–0.33) — but only realized with the
  training infrastructure the app deliberately doesn't have (no server).
- **Cost: L++.**
- **Verdict: reject** for the foreseeable future. Revisit only if the app
  ever grows an opt-in cloud component.

#### Honorable mentions (not schedulers per se)

- **SSP-MMC** ("stochastic shortest path — minimize memorization cost",
  the TKDE 2023 line of work): optimizes the *review policy* on top of a
  memory model rather than the model itself. Relevant someday for choosing a
  per-user retention target; not actionable now.
- **Anki's SM-2 variant, interval fuzz, easy-days, retention-target UI:**
  scheduling ergonomics, not algorithms; fuzzing (±5% noise on
  `schedule(days:)`) is an S-cost improvement worth considering independently
  to de-synchronize review pile-ups.

### 1.3 Part 1 verdict

| Candidate | Worth adding? | Why |
| --- | --- | --- |
| **FSRS-6 (default params)** | **Yes — replace the `.fsrs` case in place** | Biggest accuracy win available; fixes same-day-requeue blind spot; S–M cost; no new UI, no new `WordState` fields |
| **FSRS optimizer (on-device)** | Later (Phase 3) | Gain ≈ one version bump, needs ~1k reviews and graded data; do the *logging* groundwork now |
| Retrievability-based review ordering (Ebisu's practical payoff) | Yes, as a `StudyOrder` case | S cost; uses existing `FSRSScheduler.retrievability` |
| Interval fuzz | Optional, S | Prevents review-day pile-ups; pure `schedule()` tweak |
| SM-17/SM-18 | No | Proprietary, unspecified, superseded by FSRS |
| HLR | No | Below-baseline accuracy; needs population training |
| DASH family | No | Worse than shipped FSRS-4.5 |
| ACT-R | No | Below baseline |
| Ebisu as scheduler | No | Worst-in-class calibration; no difficulty model |
| Memrise ladder | No | Redundant third fixed ladder |
| Neural (GRU/LSTM/RWKV/KARL) | No | Training pipeline & interpretability conflict with local-only, user-in-charge design |

A deliberate consequence: **the four-scheduler lineup stays four.** The
differentiation between entries stays meaningful (fixed ladder / boxes /
classic adaptive / modern model), which is better UX than a museum of
also-rans. The upgrade budget is better spent on Part 2.

---

## Part 2 — Upgrading input complexity beyond binary

### 2.1 Why bother: what richer input is worth per scheduler

The binary input is the *only* reason the app's FSRS is "simplified." Concrete
value of a 4-grade signal, per existing scheduler:

- **`FSRSScheduler`**: unlocks ratings 2 (Hard) and 4 (Easy) — activating the
  already-shipped `w[15]`/`w[16]` weights, better difficulty estimation
  (difficulty updates by `−w[6]·(rating−3)`; binary input can only ever move
  difficulty by 0 or +2·w[6], while graded input adds the gentler ±1·w[6]
  steps in both directions), and eventual optimizer-quality data.
- **`SM2Scheduler`**: the algorithm was *designed* for q0–5; binary collapses
  it to {2, 4}, which can never award the +0.1 ease bonus (q=5) and never
  applies the pass-but-struggling −0.14 (q=3). Graded input restores SM-2's
  actual dynamic range.
- **`LeitnerScheduler` / `CirclesScheduler`**: modest but real — "Hard = stay
  in place" avoids the false dichotomy between "promote" and "demote to
  box 1", the single harshest artifact of the current system.

### 2.2 The canonical grade domain

Everything downstream is simplest if the app defines **one internal grade
enum** and maps every input surface onto it:

```swift
public enum ReviewGrade: Int, Codable, Sendable, CaseIterable {
    case again = 1   // failed to recall
    case hard  = 2   // recalled with serious difficulty (counts as success)
    case good  = 3   // recalled
    case easy  = 4   // recalled instantly
    public var knew: Bool { self != .again }   // binary degradation
}
```

- Chosen to be **FSRS-native** (identical to FSRS ratings 1–4) since FSRS is
  the scheduler that benefits most.
- `Scheduler` gains `apply(grade: ReviewGrade, ...)` as the primary
  requirement; the existing `apply(answer knew: Bool, ...)` becomes a
  protocol-extension shim: `apply(grade: knew ? .good : .again, ...)`. All
  call sites (`StudyEngine.answer`, `StudyModel.answer`, `SRS.apply`,
  `SchedulerTests`) keep compiling; binary mode's behavior is bit-identical to
  today by construction.

**Exact consumption mapping for the four schedulers:**

| `ReviewGrade` | Circles (`memoryCircle`) | Leitner (box) | SM-2 quality q | SM-2 ease Δ | FSRS rating |
| --- | --- | --- | --- | --- | --- |
| `.again` | reset to 1, interval 1d | box 1, 1d | 2 | −0.32 | 1 (Again) |
| `.hard` | **stay**; reschedule at current circle's interval | **stay**; reschedule current box interval | 3 (pass) | −0.14 | 2 (Hard) — success branch × `w[15]` |
| `.good` | +1 circle | +1 box | 4 | 0.00 | 3 (Good) |
| `.easy` | +2 circles | +2 boxes (capped at 5) | 5 | +0.10 | 4 (Easy) — success branch × `w[16]` |

Notes on the mapping:

- **SM-2**: q=3 is a *pass* in canonical SM-2 (interval advances, ease drops).
  The current binary mapping (know→4, forgot→2) is exactly the Good/Again rows,
  so historical behavior is a strict subset — no re-interpretation of old data.
- **FSRS**: `stabilityAfterSuccess` grows a `hardPenalty = (rating == 2 ? w[15] : 1)`
  and `easyBonus = (rating == 4 ? w[16] : 1)` factor on the growth term —
  that is the entire FSRS-side diff. `initialDifficulty(rating:)` and
  `nextDifficulty(_:rating:)` already take the rating as `Double` and need no
  change. Hard is a success (does *not* reset `memoryCircle` bookkeeping).
- **Circles/Leitner "Hard = stay, Easy = +2"** extends the fixed ladders in
  the only way that keeps them predictable (their whole selling point). In
  binary mode these branches are unreachable, so the "original app behavior"
  promise of `.circles` is untouched for default users.
- **Familiarity bookkeeping** (`Scheduler.bookkeep`) extends as:
  again −20 (unchanged), hard +10, good +20 (unchanged), easy +30 — binary
  users see identical numbers; the constants live next to
  `SRS.familiarityStepUp/Down`.
- **Requeue** (`StudyEngine.answer`): only `.again` re-queues the card
  (same insertion logic as today). `.hard` advances the session — keeping
  sessions bounded and matching the "Hard is a pass" semantics of SM-2/FSRS.

### 2.3 The input-design catalog

Every plausible design, judged against this app's actual flashcard screen
(`NeoFlashcardView`: progress header / tappable card / `bottomControls` with
two 54pt buttons; same contract in `Apps/Classic/StudyViews.swift`).

#### A. Four grade buttons (Again / Hard / Good / Easy)

- **UI.** In graded mode, `bottomControls` post-reveal shows a 4-button row
  (or 2×2 grid on narrow widths) in place of the two buttons: Again (red,
  `Neo.red` treatment like today's I Don't Know), Hard (warm/orange), Good
  (navy `Neo.blue`, the "default" visual weight), Easy (teal/green).
  Pre-reveal, keep the current contract: tapping any grade before reveal
  behaves like `answerTapped` does now (set `pendingAnswer`-style grade,
  reveal, second tap commits) — this preserves the app's fast path rather
  than forcing an Anki-style "Show Answer" bar. New accessibility ids:
  `study.grade.again` … `study.grade.easy`; `study.know`/`study.dontKnow`
  remain in binary mode.
- **Scheduler consumption.** The canonical mapping table above, directly.
- **Schema.** §2.5 only; no extra.
- **Risk.** Choice overload / grade agonizing — the known Anki failure mode.
  Mitigated by being opt-in (§2.6) and by visual hierarchy (Good is the big
  button; Hard/Easy are quieter).
- **Judgment: the primary candidate.** Highest information per tap, exact
  fit to FSRS/SM-2, industry-standard mental model.

#### B. Three grade buttons (Again / Good / Easy — or Again / Hard / Good)

- **UI.** Same placement as A with one fewer button.
- **Consumption.** Again/Good/Easy → FSRS 1/3/4, SM-2 q 2/4/5 (drops Hard);
  Again/Hard/Good → FSRS 1/2/3, SM-2 q 2/3/4 (drops Easy). The first variant
  loses the most valuable new signal (Hard is what fixes the
  pass-but-struggling case); the second loses the least harmful one.
- **Judgment: fallback, not a tier.** Shipping *both* a 3- and 4-grade option
  multiplies Settings complexity for marginal gain. Only adopt if testing
  shows 4 buttons measurably slow users down; then prefer Again/Hard/Good.

#### C. Binary + long-press modifier

- **UI.** Keep today's two buttons; long-press I Know → Easy, long-press
  I Don't Know → Hard. Haptic + label flash ("Easy") on trigger.
- **Consumption.** Same canonical mapping; short presses stay Good/Again.
- **Problems.** (1) Discoverability ≈ zero. (2) **Polarity bug baked into the
  interaction**: Hard is a *success* in every graded algorithm, but it lives
  on the failure button — users will long-press I Don't Know meaning "really
  didn't know", silently logging a pass. That's mislabeled training data at
  the source.
- **Judgment: acceptable only as an accelerator layered on A** (long-press
  Good → Easy), never as the standalone graded input.

#### D. Swipe gestures (direction ± velocity)

- **UI.** Card swipes: right = Good, left = Again, down = Hard, up = Easy
  (AnkiMobile-style). Velocity-modulated grading ("hard fling right = Easy")
  is listed for completeness.
- **Conflicts.** The card's `onTapGesture` (reveal) coexists fine, but
  vertical swipes fight scrolling if definitions ever scroll, and the screen
  currently has no undo — an accidental swipe is an unrecoverable wrong grade.
  Velocity nuance is pure noise (grip, hand size, hurry) and should never be
  a grading signal.
- **Judgment: Phase-2 optional sugar** on top of A, gated behind its own
  toggle, and only after an Undo affordance exists (a toast with "Undo" that
  re-inserts the card and rolls back `WordState` — note this also requires
  keeping the pre-answer `WordState` snapshot in `StudyModel`).

#### E. Response-time-derived implicit difficulty

- **UI.** None — that's the appeal. Measure reveal→answer latency; long
  latency demotes Good → Hard, very short promotes → Easy.
- **Problems.** (1) The `pendingAnswer` fast path answers *before* reveal, so
  the cleanest timing signal doesn't exist on that path. (2) Latency is
  confounded (notifications, thinking about the example sentence, TTS
  playback via `speakCurrent`). (3) Silently changing what the user said
  violates the app's user-in-charge principle more than any other design
  here.
- **Judgment: log it, don't act on it.** Add `response_ms` to `study_log`
  (§2.5) from day one; revisit only ever as an *opt-in* "auto-Hard" toggle,
  and as a candidate optimizer feature. Never a silent default.

#### F. Post-reveal self-rating slider (0–100)

- **UI.** A slider under the revealed definition; release commits.
- **Problems.** Slowest possible input (~1–2s per card vs ~200ms for a tap);
  false precision (nobody's memory introspection resolves 73 vs 78); the
  continuous value must be re-quantized into 4 grades for every scheduler
  anyway. The app *already has* a deliberate familiarity slider on the word
  detail page (`setFamiliarity`), which covers the "let me just set this
  myself" need in the right place.
- **Judgment: reject** for the flashcard loop.

#### G. Two-stage: binary tap, then optional refine

- **UI.** Tap I Know / I Don't Know exactly as today; the card advances, and
  for ~1.5s a transient chip appears near the tapped button: after I Know →
  "Too easy?" (upgrades to Easy); after I Don't Know → "Almost had it?"
  (upgrades to Hard). Ignoring the chip commits Good/Again.
- **Consumption.** Canonical mapping; the refined grade replaces the
  provisional one.
- **Logic cost.** The scheduler application must be **deferred to the commit
  point** (chip timeout or next answer), or applied provisionally and
  re-applied from a `WordState` snapshot on refine. `StudyModel.answer` gains
  a small pending-commit state machine; `StudyEngine.answer` needs a variant
  that can be replayed. Doable but the subtlest state management of any
  design here (interaction with pause/`persist()` mid-grace-window needs
  care).
- **Judgment: the best "zero added friction" alternative to A.** Keeps the
  two-button muscle memory perfectly; grades are strictly opt-in *per card*.
  Slightly worse data quality than A (refines will be rare) and meaningfully
  more implementation subtlety. Good Phase-2 candidate if A's buttons feel
  heavy.

#### H. Typing / recall tests (objective grading)

- **UI.** A separate opt-in study mode ("Spell it"): show translation
  (`DictWord.translationLines`) ± phonetic, user types the word; grade
  computed from edit distance and reveal usage: exact = Good (fast exact =
  Easy), 1 edit or self-corrected = Hard, gave up / revealed = Again.
  `DictWord.exchangeForms` lets the checker accept inflected forms
  knowingly.
- **Value.** The only *objective* grading source in this list, and it tests
  production rather than recognition — a genuinely different (stronger)
  memory task. Also the only design that grades without any self-assessment
  bias, which is ideal future optimizer data.
- **Cost: L.** A new card UI, keyboard management, answer normalization,
  per-mode session plumbing (`StudyMode` today is Mix/AllNew/AllReview —
  orthogonal to card format, so a new `CardFormat` axis, not a new
  `StudyMode` case).
- **Judgment: Phase 3.** Worth doing eventually; irrelevant to the
  grade-plumbing decision because it *emits* the same `ReviewGrade`.

### 2.4 Feasibility matrix

Benefit = signal quality × how much the schedulers can use it.
Cost = engineering incl. both frontends. Risk = UX regression + data-quality
+ state-machine complexity.

| Design | Benefit | Cost | Risk | Verdict |
| --- | --- | --- | --- | --- |
| A. 4-grade buttons | High | M | Low–Med | **Ship as the opt-in graded mode (Phase 1)** |
| B. 3-grade buttons | Med | S–M | Low | Fallback only if A tests poorly |
| C. Long-press modifier | Low–Med | S | Med (polarity mislabeling) | Only as accelerator on A |
| D. Swipe gestures | Med | M | Med (accidental grades, needs Undo) | Phase 2, own toggle |
| E. Response-time implicit | Med (as data) | S (log) / M (act) | High if silent | Log now, act never-by-default |
| F. Self-rating slider | Low | S | Med (friction) | Reject |
| G. Two-stage refine | Med–High | M (state machine) | Med | Phase 2 alternative/complement to A |
| H. Typing tests | High (objective) | L | Low–Med | Phase 3 feature |

### 2.5 Schema, `WordState`, and backwards compatibility

**`study_log`** (the important one — this is future optimizer food), via the
existing tolerant-`ALTER TABLE` pattern in `UserStore.migrate()`:

```sql
ALTER TABLE study_log ADD COLUMN grade INTEGER;        -- 1-4; NULL = legacy binary row
ALTER TABLE study_log ADD COLUMN response_ms INTEGER;  -- reveal→answer latency; NULL on fast path
ALTER TABLE study_log ADD COLUMN elapsed_days REAL;    -- since previous review of this word
ALTER TABLE study_log ADD COLUMN scheduled_days REAL;  -- what the scheduler had planned
```

- `knew` stays and stays authoritative for `todayCounts()`; the invariant is
  `knew = (grade IS NULL AND knew) OR grade >= 2`. Legacy rows need no
  backfill: `NULL` grade *means* "binary era", and any consumer maps it to
  `knew ? good : again` — the same mapping the schedulers have applied all
  along, so historical data is not reinterpreted, merely re-expressed.
- `elapsed_days`/`scheduled_days` make the log self-contained for an
  optimizer (no fragile reconstruction across word-key case differences), and
  cost nothing to write since `WordState.lastStudiedAt`/`intervalDays` are in
  hand inside `StudyModel.answer`.
- `UserStore.logStudy` gains optional parameters with defaults, so existing
  call sites compile unchanged.

**`word_state` / `WordState`: no new columns required.** The 4-grade upgrade
runs entirely on existing fields (`memoryCircle`, `intervalDays`,
`easeFactor`, `stability`, `difficulty`). Optional nicety: a `lapses INTEGER`
column for stats screens — not needed by any scheduler above, so defer.

**`StudySession`** (Codable, persisted via `StudyEngine.encode/decode` into
`session_state.payload`): unchanged. Grades are consumed at answer time and
never stored in the queue, so paused pre-upgrade sessions decode and resume
fine.

**Settings.** One new `AppSettings` key, mirroring the `scheduler` pattern:

```swift
public enum AnswerStyle: String, CaseIterable, Codable, Sendable {
    case simple   // I Know / I Don't Know (default — current behavior)
    case graded   // Again / Hard / Good / Easy
}
// Key.answerStyle = "settings.answerStyle"; getter defaults to .simple
```

Surfaced in both `Apps/Redesign/NeoSettingsView.swift` and
`Apps/Classic/SettingsView.swift` next to the existing Algorithm picker,
with a footer explaining the mapping ("Simple answers count as Good/Again").

**The user-freedom guarantees, extended:**

1. Binary remains the default; `.graded` is opt-in per Settings — new users
   see zero change.
2. Switching answer style never invalidates progress, in either direction:
   graded answers degrade to binary via `ReviewGrade.knew`; binary answers
   are canonically `good`/`again`. All four schedulers accept both streams
   interleaved (they already do — that *is* the current binary mapping).
3. Algorithm switching stays orthogonal to answer style (any of 4 × 2
   combinations is valid), preserving the `SchedulerKind` doc-comment
   contract that unused fields are carried along.
4. Manual familiarity edits keep working unchanged (`setFamiliarity` is
   outside the scheduler path).
5. `SRS.apply` (the legacy binary circles path used by seed/compat code)
   keeps its signature; it simply remains the `.good/.again` special case.

### 2.6 Recommended roadmap

**Phase 1 — grade plumbing + opt-in 4-grade mode** (the core; ~M total)
1. Add `ReviewGrade` to VocabKit; extend `Scheduler` with
   `apply(grade:to:now:calendar:)`; keep the `Bool` overload as a shim.
2. Implement the mapping table in all four schedulers (FSRS: activate
   `w[15]`/`w[16]`; SM-2: q∈{2,3,4,5}; Circles/Leitner: stay/skip rules).
3. `study_log` columns + `logStudy` extension; write `grade`,
   `elapsed_days`, `scheduled_days`, `response_ms` from `StudyModel.answer`.
4. `AppSettings.answerStyle` + pickers in both Settings views.
5. Graded `bottomControls` in `NeoFlashcardView` and the Classic equivalent;
   preserve the pre-reveal fast path; extend `SchedulerTests` with
   graded-vs-binary equivalence tests (binary mode must stay bit-identical).

**Phase 2 — model upgrade + input polish** (~M)
1. Upgrade `FSRSScheduler` from 4.5 to FSRS-6 defaults (or adopt
   `swift-fsrs`): same-day-review handling (fixes the in-session requeue
   blind spot), learnable-decay-ready curve. Keep `stability`/`difficulty`
   columns as-is.
2. Undo affordance in the flashcard loop (prerequisite for gestures).
3. Optional accelerators behind toggles: swipe grading (D), long-press
   Good→Easy (C), or the two-stage refine chip (G) if 4 buttons test heavy.
4. "Most at risk first" `StudyOrder` case using
   `FSRSScheduler.retrievability`; optional ±5% interval fuzz in
   `schedule()`.

**Phase 3 — personalization + objective input** (L, only if the app's data
justifies it)
1. On-device FSRS optimizer (pure-Swift Adam over log loss, or `fsrs-rs`
   FFI), triggered manually from Settings once ≥ ~1,000 logged reviews;
   store per-user weights in `AppSettings`; show "using personalized
   parameters" in the algorithm summary.
2. Configurable retention target (the `targetRetention = 0.9` constant
   becomes a Settings value, 0.8–0.95).
3. "Spell it" typing mode (H) emitting objective `ReviewGrade`s.

### 2.7 What *not* to do

- Don't add a fifth scheduler for the sake of the list (Memrise, Ebisu, DASH,
  HLR, ACT-R, SM-18, neural) — every one is dominated by upgrading FSRS in
  place or is infrastructure the app deliberately lacks.
- Don't ship both 3- and 4-grade tiers.
- Don't infer grades from response time or swipe velocity by default.
- Don't put Hard on the failure button (design C standalone).
- Don't block graded input on the optimizer, or vice versa — they are
  independent; the only coupling is that graded logs make future optimization
  better, which is exactly why the schema work is Phase 1.

---

## Sources

- srs-benchmark (open-spaced-repetition): https://github.com/open-spaced-repetition/srs-benchmark
- Benchmark commentary: https://expertium.github.io/Benchmark.html · FSRS technical explanation: https://expertium.github.io/Algorithm.html
- FSRS-6 discussion: https://github.com/orgs/open-spaced-repetition/discussions/30 · FSRS wiki: https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
- Swift FSRS: https://github.com/open-spaced-repetition/swift-fsrs · optimizer: https://github.com/open-spaced-repetition/fsrs-rs · ecosystem: https://github.com/open-spaced-repetition/awesome-fsrs
- SuperMemo SM-17/SM-18: https://supermemo.guru/wiki/Algorithm_SM-17 · https://supermemo.guru/wiki/Algorithm_SM-18
- HLR: Settles & Meeder, ACL 2016 — https://research.duolingo.com/papers/settles.acl16.pdf · https://github.com/duolingo/halflife-regression
- Ebisu: https://github.com/fasiha/ebisu · https://fasiha.github.io/ebisu/
- DASH / DAS3H: https://files.eric.ed.gov/fulltext/ED599174.pdf · Khajah, Lindsey & Mozer 2013: https://home.cs.colorado.edu/~mozer/Research/Selected%20Publications/reprints/KhajahLindseyMozer2013.pdf
- KARL: https://arxiv.org/abs/2402.12291
- SSP-MMC: "Optimizing Spaced Repetition Schedule by Capturing the Dynamics of Memory", IEEE TKDE 2023 — https://dl.acm.org/doi/10.1109/TKDE.2023.3251721
