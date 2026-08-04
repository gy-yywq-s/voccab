# Memory-scheduling algorithms

Voccab lets the user choose the spaced-repetition algorithm in
Settings → Study → Algorithm. All algorithms consume the same binary study
input (I Know / I Don't Know), share the same familiarity bookkeeping
(±20%, clamped to 0–100%), and store their state side by side, so switching
algorithms never loses progress.

Implementation: `Packages/VocabKit/Sources/VocabKit/Scheduler.swift`.
Tests: `Packages/VocabKit/Tests/VocabKitTests/SchedulerTests.swift`.

## Research summary

Spaced repetition rests on two robust findings from memory research:

- **The forgetting curve** (Ebbinghaus, 1885): recall probability decays
  roughly exponentially with time since the last review.
- **The spacing effect**: reviews spaced just before forgetting produce far
  more durable memory per minute of study than massed repetition, and each
  successful spaced recall slows subsequent forgetting.

Modern schedulers differ in how they estimate when a word is about to be
forgotten:

| Algorithm | Year | Per-word model | Strengths | Weaknesses |
| --- | --- | --- | --- | --- |
| Fixed ladder ("memory circles") | — | none (global ladder) | predictable, matches the original app | ignores item difficulty |
| Leitner boxes | 1972 | box number | dead simple, physical-flashcard heritage | coarse, resets hard |
| SM-2 (SuperMemo) | 1987 | ease factor | first per-item adaptivity; the Anki default for decades | ease "death spiral" on repeated failures |
| FSRS 4.5 | 2023 | stability + difficulty (DSR model) | best published fit to real review logs; explicit retention target | more complex; benefits from personalized weights |

## What each implementation does

### Memory Circles (default — the original app's behavior)

Success advances one circle on the ladder **1, 2, 4, 7, 15, 30** days
(doubling past the ladder); failure resets to circle 1. The word detail page
shows the circle number ("Memory: Circle 2").

### Leitner Boxes

Five boxes with intervals **1, 2, 4, 8, 16** days. Success promotes one box,
failure demotes to box 1. The box number is stored in the same field as the
circle number.

### SM-2

Every word carries an ease factor `EF` starting at 2.5. Binary answers map to
SM-2 quality grades (know → q=4, forgot → q=2):

```
EF' = max(1.3, EF + 0.1 − (5−q)(0.08 + (5−q)·0.02))
I(1) = 1 day, I(2) = 6 days, I(n) = I(n−1) × EF
```

Failure resets the repetition count (next interval 1 day) while keeping the
shrunken ease, so difficult words cycle faster permanently.

### FSRS (4.5, simplified)

FSRS models each word as (Stability, Difficulty). Retrievability after `t`
days is

```
R(t, S) = (1 + (19/81)·t/S)^(−0.5)
```

and the next interval is chosen so R ≈ 0.9 (with the standard constants the
interval approximately equals the stability). On review, stability grows by

```
S' = S · (1 + e^{w8} · (11 − D) · S^{−w9} · (e^{w10·(1−R)} − 1))
```

for a success, and collapses to

```
S'_fail = min(S, w11 · D^{−w12} · ((S+1)^{w13} − 1) · e^{w14·(1−R)})
```

on a failure. Difficulty moves with each answer and mean-reverts toward its
initial "Good" value. We use the published FSRS-4.5 default weights and map
the binary input to Good/Again ratings.

Simplifications versus full FSRS: no per-user weight optimization (needs a
review-log training step), no Hard/Easy grades (the UI is binary by design),
and no fuzzing of intervals. These keep behavior deterministic and the UI
unchanged; the data model already stores everything needed to add weight
training later.

## User freedom

- The algorithm, recitation order, daily goals, and target familiarity are
  all independent settings.
- The scheduler only decides *when* a word comes back; *what* is studied and
  in *which order* stays under the user's control (study order setting +
  per-session override).
- Manual familiarity edits (slider or "Feel Familiar?" menu) are always
  respected regardless of algorithm.
