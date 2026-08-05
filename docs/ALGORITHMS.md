# Memory-scheduling algorithms

Voccab lets the user choose the spaced-repetition algorithm in
Settings → Practice → Algorithm. Every algorithm consumes the same study
input (binary or graded, per the Practice Input setting), shares the same
Ebisu recall observer, and stores its state side by side, so switching
algorithms never loses progress. A guarded switch flow previews what a
change auto-converts before it happens.

Implementation: `Packages/VocabKit/Sources/VocabKit/Schedulers/` — one file
per algorithm, plus `SchedulerCore.swift` (shared protocol + bookkeeping),
`SchedulerKind.swift` (registry), `AlgorithmConfig.swift` (per-algorithm
knobs), `SSPMMC.swift` (scheduling goal), `FSRSOptimizer.swift`
(on-device personalization).
Tests: `Packages/VocabKit/Tests/VocabKitTests/SchedulerTests.swift`.

## The lineup

| Algorithm | Year | Scale | Per-word model | Character |
| --- | --- | --- | --- | --- |
| Memory Circles | — | days | ladder rung | the original app's fixed 1·2·4·7·15·30 ladder |
| Leitner Boxes | 1972 | days | box number | physical-flashcard heritage, doubling boxes |
| Memrise Ladder | — | **hours** | ladder rung | 4h → 12h → 24h → 6d…: same-day reinforcement first |
| Pimsleur Burst | 1967 | **seconds** | ladder rung | 5s → 25s → 2m → …: rapid same-session cramming |
| SM-2 | 1987 | days | ease factor | classic SuperMemo adaptivity |
| FSRS-6 | 2024 | days | stability + difficulty | mainline modern model, 21 parameters, learnable decay |
| FSRS-7 | 2026 | **fractional** | stability + difficulty | newest model, 35 parameters, dual forgetting curves, native same-day handling |

FSRS-6 and FSRS-7 are ports of the official open-spaced-repetition
implementations (swift-fsrs and srs-benchmark reference, MIT). The
hour-scale algorithms schedule with exact timestamps; day-scale algorithms
keep calendar-day anchoring.

## Graded input

Grades map per algorithm (spelled out in Settings → Practice Input):
ladders treat Hard as "hold the rung" and Easy as "climb two"; SM-2 maps
grades to its native quality 2–5; FSRS uses ratings 1–4 directly,
activating the Hard-penalty and Easy-bonus weights binary input can't
reach. Binary mode is bit-identical to the historical behavior
(know → Good, forgot → Again).

## The Ebisu recall observer

`Ebisu.swift` is an explicit Swift implementation of Ebisu v2 (Bayesian
Beta-on-recall). It is deliberately **not** a scheduler (it benchmarks
below baseline as one); instead it runs as an independent observer updated
by every review under every algorithm, and its `predictRecall` powers the
recall display, the recall filters, and the "Recall (Weakest First)" study
order — the slot the old familiarity counter occupied before it was
removed.

## Scheduling goals (FSRS-6/7)

- **Target retention** (default): every interval aims for the configured
  recall probability (85/90/95%).
- **Minimize total cost (SSP-MMC)**: a greedy one-step version of the
  SSP-MMC objective (Ye et al., TKDE 2023) — each review picks the
  retention that maximizes expected stability gained per second of
  expected review time.

## Graduation

"By algorithm" uses each algorithm's native endpoint: ladders retire past
their top rung (configurable), SM-2 uses a practical interval horizon, and
the FSRS family graduates on **stability** ≥ horizon (retention-knob
independent). "Never" keeps everything cycling.

## Personalization

Settings → Algorithm Settings → Personalization fits the 21 FSRS-6
parameters to the user's own review log (log-loss objective, Adam with
numerical gradients, on-device, ≥400 reviews). The result is kept only if
it beats the defaults on the user's own data, and can be reverted anytime.
The review log records grade, response time, and interval context (user
can disable) — the raw material this and any future tuning needs.

## User freedom

- Algorithm, input style, scheduling goal, graduation policy, order, and
  daily goals are independent settings.
- The scheduler decides *when* a word comes back; *what* is studied and in
  *which order* stays under the user's control.
- Switching algorithms previews auto-conversions, is cancelable, and
  highlights converted settings once afterwards.
