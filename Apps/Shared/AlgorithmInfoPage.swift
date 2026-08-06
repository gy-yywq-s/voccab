import SwiftUI
import VocabKit

/// A per-algorithm reference page, reached from the expanded rows of
/// AlgorithmPreviewPage. One scrollable column: the algorithm's name set in
/// a serif face, a one-line essence, the shared eight-review simulation as a
/// visual signature, then quiet uppercase sections — how it works, the state
/// it keeps, its history, its benchmark standing, when to pick it, and how
/// this app wires it up. Prose is factual; the one or two formulas shown per
/// algorithm are rendered as monospaced blocks.
struct AlgorithmInfoPage: View {
    let kind: SchedulerKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 20)
                    .padding(.bottom, 24)

                signature
                    .padding(.bottom, 28)

                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    Divider()
                    sectionView(section.title, section.blocks)
                        .padding(.vertical, 22)
                }
                Divider()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header + simulation signature

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.label)
                .font(Font.custom("Iowan Old Style", size: 32, relativeTo: .largeTitle))
                .foregroundStyle(.primary)
            Text(Self.essence(kind))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The same eight-review story every algorithm is compared on, rendered
    /// with the real scheduler — the page's visual signature.
    private var signature: some View {
        let sim = AlgorithmPreviewPage.simulation(for: kind)
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(sim.steps.enumerated()), id: \.offset) { _, step in
                        VStack(spacing: 3) {
                            Image(systemName: step.knew ? "checkmark" : "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(step.knew ? Color.green : Color.red)
                            Text(Formatting.interval(days: step.intervalDays))
                                .font(.footnote.monospacedDigit().weight(.semibold))
                        }
                        .frame(minWidth: 40)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(step.knew
                                      ? Color(uiColor: .secondarySystemBackground)
                                      : Color.red.opacity(0.12))
                        )
                    }
                }
            }
            Text("The shared benchmark story — five correct answers, one miss, two recoveries — replayed on the real scheduler. A perfect run reaches \(Formatting.interval(days: sim.perfectTotalDays)); the one miss cuts that to \(Formatting.interval(days: sim.missTotalDays)).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Section rendering

    private enum Block {
        case text(String)
        case formula(String)
        case bullets(String?, [String])   // optional lead-in label + bullet lines
    }

    private func sectionView(_ title: String, _ blocks: [Block]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .formula(let formula):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(formula)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        case .bullets(let label, let lines):
            VStack(alignment: .leading, spacing: 6) {
                if let label {
                    Text(label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("·")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tertiary)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var sections: [(title: String, blocks: [Block])] {
        [("How it works", Self.how(kind)),
         ("Structure", Self.structure(kind)),
         ("History", Self.history(kind)),
         ("Research", Self.research(kind)),
         ("When to use", Self.whenToUse(kind)),
         ("In this app", Self.inThisApp(kind))]
    }

    // MARK: Content — essence

    private static func essence(_ kind: SchedulerKind) -> String {
        switch kind {
        case .circles:
            return "A fixed Ebbinghaus-style review ladder."
        case .leitner:
            return "The 1972 card-box system that started systematized flashcards."
        case .memrise:
            return "An hour-scale fixed ladder built around same-day reinforcement."
        case .pimsleur:
            return "The first published graduated-interval schedule (1967) — built for cramming a session, not a semester."
        case .sm2:
            return "The 1987 SuperMemo algorithm — Anki's ancestor — where each word earns its own ease factor."
        case .fsrs:
            return "The mainline modern memory model: per-word difficulty, stability, and a live forgetting curve."
        case .fsrs7:
            return "The newest FSRS (2026): dual forgetting curves, hour-scale intervals, and the best benchmark score of any small model."
        }
    }

    // MARK: Content — how it works

    private static func how(_ kind: SchedulerKind) -> [Block] {
        switch kind {
        case .circles:
            return [
                .text("Memory Circles walks every word up the same fixed ladder of waiting times. Answer correctly and the word climbs one rung; the wait until the next review is that rung's preset interval. Past the top of the ladder the interval simply keeps doubling. Miss once and the word falls all the way back to the first rung — one day — and starts the climb again."),
                .formula("1d → 2d → 4d → 7d → 15d → 30d → (×2 …)"),
                .text("There is no per-word adaptation: an easy word and a stubborn word walk the same stairs at the same speed. What varies is only how often each word falls."),
            ]
        case .leitner:
            return [
                .text("Picture five physical boxes reviewed at increasing intervals. Every card starts in box 1. Answer correctly and the card is promoted one box; miss and it returns to box 1, whichever box it was in. Each box has a fixed waiting time:"),
                .formula("box 1 · 1d    box 2 · 2d    box 3 · 4d    box 4 · 8d    box 5 · 16d"),
                .text("A card that passes the top box has survived the whole gauntlet and can retire from review."),
            ]
        case .memrise:
            return [
                .text("The ladder starts within the day you learn a word: the first reviews come back after hours, not days, so a new word is reinforced while it is still fresh. Passes climb the fixed rungs; a miss resets the word to the 4-hour rung."),
                .formula("4h → 12h → 24h → 6d → 12d → 48d → 96d → 180d"),
                .text("The shape front-loads effort — three same-day-or-next-day touches — and then stretches quickly to multi-month gaps."),
            ]
        case .pimsleur:
            return [
                .text("Intervals begin at five seconds and multiply by roughly five each step, from within-the-minute echoes all the way to multi-year gaps:"),
                .formula("5s → 25s → 2m → 10m → 1h → 5h → 1d → 5d → 25d → 4mo → 2y"),
                .text("The early rungs are the point: a new word comes back before you can forget it, again and again inside one sitting. Uniquely among the ladders, a miss drops the word only one rung — a gentle regression, because with second-scale intervals a full reset would be meaningless."),
            ]
        case .sm2:
            return [
                .text("SM-2 was the first algorithm to give every item its own memory. Each word carries an ease factor, EF — a personal growth multiplier. The first two intervals are fixed; from the third review on, each interval is the previous one times EF:"),
                .formula("I(1) = 1d    I(2) = 6d    I(n) = I(n−1) × EF"),
                .text("Every answer nudges EF according to its quality q on a 0–5 scale — confident answers push it up, hesitant ones pull it down. EF starts at 2.5 and is floored at 1.3:"),
                .formula("EF′ = EF + 0.1 − (5 − q) · (0.08 + (5 − q) · 0.02)"),
                .text("A miss restarts the interval sequence from I(1), but the lowered EF persists — so a word you keep missing grows back more slowly each time."),
            ]
        case .fsrs:
            return [
                .text("FSRS models each word with three quantities: Difficulty (how hard the word is), Stability (how many days the memory holds), and Retrievability (the probability you would recall it right now). Recall probability decays along a power-law forgetting curve:"),
                .formula("R(t, S) = (1 + FACTOR · t / S) ^ DECAY"),
                .text("The next review is scheduled for the moment R is predicted to fall to your target retention (85, 90, or 95%). A successful review multiplies stability by a factor that is larger for easier words, for fragile memories, and for reviews you were on the verge of forgetting:"),
                .formula("S′ = S · (1 + e^{w8} · (11 − D) · S^{−w9} · (e^{w10·(1−R)} − 1)\n         · hardPenalty · easyBonus)"),
                .text("FSRS-6 has 21 trainable parameters, including a learnable decay (w20) for the forgetting curve itself, plus a separate short-term branch for same-day reviews. A miss collapses stability to a small fraction and raises difficulty."),
            ]
        case .fsrs7:
            return [
                .text("FSRS-7 keeps the difficulty–stability–retrievability core of FSRS but splits memory in two: a long-term and a short-term stability system, identical in functional form, blended by a continuous transition that depends on how recently the word was seen:"),
                .formula("blend weight = 1 − w26 · e^{−w25 · Δt}"),
                .text("Forgetting follows a dual power-law curve — two curves mixed with stability-dependent weights — instead of a single curve. Intervals are fractional, so early reviews are scheduled in hours, and FSRS-7 is the only FSRS version that predicts same-day reviews realistically rather than special-casing them."),
                .text("It has 35 trainable parameters, and its shipped default parameters behave like an already-optimized FSRS-4.5."),
            ]
        }
    }

    // MARK: Content — structure

    private static func structure(_ kind: SchedulerKind) -> [Block] {
        switch kind {
        case .circles:
            return [.text("The scheduler keeps a single number per word: its current rung — the word's memory circle. A pass writes rung + 1, a miss writes rung 1. Nothing else is read or written, which is why switching to or from this algorithm never loses progress.")]
        case .leitner:
            return [.text("One number per word: its current box. Promotion writes box + 1, a miss writes box 1. With graded input, Hard keeps the card where it is and Easy jumps it two boxes.")]
        case .memrise:
            return [.text("One rung index per word, like the other ladders. The rungs below one day are what set it apart: the scheduler works at hour precision, so a session in the morning can queue the same word again in the evening.")]
        case .pimsleur:
            return [.text("One rung index per word, at second-to-year precision. Pass climbs one rung, a miss drops one, Hard holds, Easy climbs two.")]
        case .sm2:
            return [.text("Per word: the ease factor, a repetition counter, and the last interval. A pass advances the counter and multiplies the interval; a miss resets the counter to the start of the sequence while EF keeps its reduced value.")]
        case .fsrs:
            return [.text("Per word: stability in days, difficulty on a 1–10 scale, and the time of the last review — from which retrievability is computed on demand. There is no ladder rung and no fixed sequence; the interval is simply however long it takes predicted recall to reach the target.")]
        case .fsrs7:
            return [.text("Per word: the same stability, difficulty, and last-review fields as FSRS-6, with stability tracked at hour precision and shaped by the short-term system right after learning. The interval is still the time until predicted recall hits the target retention.")]
        }
    }

    // MARK: Content — history

    private static func history(_ kind: SchedulerKind) -> [Block] {
        switch kind {
        case .circles:
            return [.text("The ladder's shape follows Hermann Ebbinghaus's 1885 forgetting-curve work: reviews spaced at roughly doubling intervals, dense at first and sparse later. This particular 1·2·4·7·15·30 sequence is the schedule the original Voccab app shipped with, and it is kept as the default for continuity with existing progress.")]
        case .leitner:
            return [.text("Sebastian Leitner, a German science journalist, described the system in his 1972 book \u{201C}So lernt man lernen\u{201D} (\u{201C}How to Learn to Learn\u{201D}). It was designed for physical index cards sorted between real boxes, and it is the oldest systematized flashcard method — the mental model behind nearly every spaced-repetition app since.")]
        case .memrise:
            return [.text("This is the hour-scale ladder popularized by the Memrise app, whose planting-and-watering metaphor turned same-day reinforcement into a mainstream product. The design encodes a laboratory result older than any app: the first repetitions after learning matter far more than the later ones.")]
        case .pimsleur:
            return [.text("Paul Pimsleur published this exact schedule in \u{201C}A Memory Schedule\u{201D} (The Modern Language Journal, 1967) — the first graduated-interval recall schedule in print. It was designed for his audio language courses, where a word must be recalled seconds after it is first heard, and it predates every computerized spaced-repetition system.")]
        case .sm2:
            return [.text("Piotr Wozniak devised SM-2 in 1987 for SuperMemo, the first computerized spaced-repetition system. Its descendants powered SuperMemo for decades, and Anki's default scheduler is a direct modification of it — arguably making SM-2 the most-used scheduling algorithm in history.")]
        case .fsrs:
            return [.text("FSRS — the Free Spaced Repetition Scheduler — comes from the open-spaced-repetition project and builds on the DSR (difficulty, stability, retrievability) line of memory-model research. FSRS-6 is the 2024 mainline release and the basis of Anki's modern scheduler. This app's port follows the official swift-fsrs implementation.")]
        case .fsrs7:
            return [.text("FSRS-7 is the 2026 release of the open-spaced-repetition scheduler line, succeeding FSRS-6 with the short-term stability system and dual forgetting curve. This app's implementation is ported from the official srs-benchmark reference implementation.")]
        }
    }

    // MARK: Content — research

    private static func research(_ kind: SchedulerKind) -> [Block] {
        switch kind {
        case .circles:
            return [.text("Fixed ladders demonstrate the spacing effect — one of the most replicated results in memory research — but ignore item difficulty. Every adaptive algorithm on the comparison page exists because a one-size-fits-all ladder over-reviews easy words and under-reviews hard ones. Modern benchmarks score only algorithms that predict recall probability, so a fixed ladder has no benchmark standing to report.")]
        case .leitner:
            return [.text("Like all fixed schedules it applies the spacing effect without modeling it, so there is no forgetting curve to benchmark. Its virtue is legibility — you can always say exactly why a card is due today. Its known weakness is the harsh penalty at the top: a lapse in box 5 costs the full 31-day climb back from box 1.")]
        case .memrise:
            return [.text("Front-loaded schedules match the steep early portion of the forgetting curve, and the early-rung design is directly supported by spacing-effect studies of initial acquisition. At long range, though, the ladder is as blind to item difficulty as any fixed sequence — and with no probability model there is nothing for modern benchmarks to score.")]
        case .pimsleur:
            return [.text("Each interval is about five times the previous — an early statement of the exponential-spacing intuition that adaptive systems later formalized. The 1967 paper is a landmark of applied memory research, but the schedule itself has no recall model to benchmark and was never designed for multi-year efficiency.")]
        case .sm2:
            return [.text("In the srs-benchmark evaluation — about 10,000 users and roughly 700 million real reviews — SM-2 sits in the bottom tier: modern models predict recall substantially better. Its documented failure mode is \u{201C}ease hell\u{201D}: repeated misses grind the ease factor toward its 1.3 floor, after which intervals grow so slowly a word can feel stuck in the review queue forever.")]
        case .fsrs:
            return [.text("On srs-benchmark — about 10,000 users, roughly 700 million real reviews — FSRS-6 achieves a log loss of 0.3460, while SM-2 ranks in the bottom tier. Because all 21 parameters are trainable, the model can also be fitted to one person's history; this app ships that optimizer and runs it on-device.")]
        case .fsrs7:
            return [.text("On srs-benchmark FSRS-7 reaches a log loss of 0.3437 — the best result among small models, ahead of FSRS-6's 0.3460 (about 10,000 users, roughly 700 million reviews). Much of the gain comes from the short-term system: real review logs are full of same-day reviews that earlier models handled poorly.")]
        }
    }

    // MARK: Content — when to use

    private static func whenToUse(_ kind: SchedulerKind) -> [Block] {
        switch kind {
        case .circles:
            return [
                .bullets("Choose it when", [
                    "You want completely predictable review dates.",
                    "You want the most predictable schedule there is — the same ladder for every word.",
                    "Your words are of fairly uniform difficulty.",
                ]),
                .bullets("Look elsewhere when", [
                    "Your deck mixes easy and hard words — an adaptive scheduler spends the same reviews better.",
                    "A full reset on every miss feels too punishing for long-interval words.",
                ]),
            ]
        case .leitner:
            return [
                .bullets("Choose it when", [
                    "You want the simplest possible mental model — five boxes, one rule.",
                    "You are learning how spaced repetition works and want to see it plainly.",
                    "Your deck is small enough that box-1 resets stay cheap.",
                ]),
                .bullets("Look elsewhere when", [
                    "You miss often — every lapse restarts the full 31-day climb.",
                    "You want intervals that adapt to each word's difficulty.",
                ]),
            ]
        case .memrise:
            return [
                .bullets("Choose it when", [
                    "You learn batches of new words and can revisit them later the same day.",
                    "Your habit is several short sessions a day rather than one long one.",
                ]),
                .bullets("Look elsewhere when", [
                    "You open the app once a day — the 4h and 12h rungs just collapse into tomorrow.",
                    "You want long-range intervals that adapt per word.",
                ]),
            ]
        case .pimsleur:
            return [
                .bullets("Choose it when", [
                    "You are cramming for this week — a test on Friday, a trip on Monday.",
                    "You want a new batch drilled to fluency inside a single session.",
                    "Harsh resets demotivate you — a miss here costs only one rung.",
                ]),
                .bullets("Look elsewhere when", [
                    "You are on a months-long program like SAT prep — second-scale rungs spend taps that longer ladders don't need.",
                    "You study strictly once a day, which skips the schedule's whole early half.",
                ]),
            ]
        case .sm2:
            return [
                .bullets("Choose it when", [
                    "You want adaptivity you can still reason about — one multiplier per word.",
                    "You mostly answer correctly, letting intervals stretch to months.",
                    "You want the algorithm three decades of flashcard users grew up on.",
                ]),
                .bullets("Look elsewhere when", [
                    "You miss the same words repeatedly — ease hell is SM-2's known trap.",
                    "You want the measurably better predictions of a fitted memory model.",
                ]),
            ]
        case .fsrs:
            return [
                .bullets("Choose it when", [
                    "You care about long-term efficiency on a mixed-difficulty deck.",
                    "You want one knob — target retention — to trade workload against recall.",
                    "You have review history to personalize with the on-device optimizer.",
                ]),
                .bullets("Look elsewhere when", [
                    "You are cramming for this week — FSRS optimizes durable memory, not tomorrow morning.",
                    "You want fixed, predictable review dates.",
                ]),
            ]
        case .fsrs7:
            return [
                .bullets("Choose it when", [
                    "You want the most accurate scheduler in the app, full stop.",
                    "You are fine with early reviews landing later the same day.",
                    "You want new words handled at hour scale instead of a coarse one-day floor.",
                ]),
                .bullets("Look elsewhere when", [
                    "You study strictly once a day and hour-scale scheduling would go unused.",
                    "You want personalized parameters — the on-device optimizer currently fits FSRS-6.",
                ]),
            ]
        }
    }

    // MARK: Content — in this app

    /// Behaviors common to every scheduler in this app.
    private static let sharedAppLines: [String] = [
        "A word missed during a session is requeued a few cards ahead and must be answered correctly before the session lets it go.",
        "The recall percentage shown on word cards comes from the separate Ebisu observer — it estimates memory for display, while scheduling belongs entirely to the algorithm you choose.",
    ]

    private static func inThisApp(_ kind: SchedulerKind) -> [Block] {
        let specific: [String]
        switch kind {
        case .circles:
            specific = [
                "Binary answers map know → climb one circle, forgot → back to circle 1. With graded input, Hard holds the current circle and Easy climbs two.",
                "Graduation is a picker in Algorithm Settings: after the 15-day review, the 30-day review (the full ladder, default), or the 60-day review.",
            ]
        case .leitner:
            specific = [
                "Binary answers map know → promote one box, forgot → box 1. With graded input, Hard stays put and Easy jumps two boxes.",
                "\u{201C}Retire after top box\u{201D} (on by default) follows the paper tradition: a card passing box 5 leaves the system. Turned off, words cycle at 16 days forever.",
                "Words arriving from a longer-interval algorithm continue at the top-box interval.",
            ]
        case .memrise:
            specific = [
                "Binary answers map know → climb one rung, forgot → back to the 4-hour rung. With graded input, Hard holds and Easy climbs two.",
                "\u{201C}Retire after top rung\u{201D} (on by default): a word passing the 180-day rung leaves the system. Turned off, words cycle at 180 days.",
                "Early rungs are hour-scale, so reviews can land within the same day.",
            ]
        case .pimsleur:
            specific = [
                "Binary answers map know → climb one rung, forgot → drop one rung (Pimsleur's gentle regression). With graded input, Hard holds and Easy climbs two.",
                "\u{201C}Retire after top rung\u{201D} (on by default): a word passing the 2-year rung leaves the system.",
                "The second- and minute-scale rungs mean a new word repeats within the session, exactly as Pimsleur intended.",
            ]
        case .sm2:
            specific = [
                "Binary answers map know → quality 4 and forgot → quality 2; graded input maps Again / Hard / Good / Easy to q = 2 / 3 / 4 / 5, driving the ease factor exactly as designed.",
                "Words that arrive without an ease factor start at SM-2's default 2.5 on their next review.",
                "Graduation is a horizon on the interval — 90, 180, or 365 days — set in Algorithm Settings, since SM-2 is perpetual in theory.",
            ]
        case .fsrs:
            specific = [
                "Binary answers map know → Good and forgot → Again; graded input becomes FSRS ratings 1–4, activating the Hard-penalty and Easy-bonus weights binary input can't reach.",
                "Algorithm Settings offers target retention (85 / 90 / 95%), a scheduling goal (fixed retention, or the SSP-MMC minimize-cost policy), and ±5% interval fuzz so reviews don't pile onto the same day.",
                "\u{201C}Optimize from my history\u{201D} fits the 21 parameters to your own review log on-device, and keeps the result only if it beats the defaults on your data.",
                "Graduation is a horizon on stability — the days a memory holds at 90% recall — so changing target retention never moves the finish line.",
            ]
        case .fsrs7:
            specific = [
                "Binary answers map know → Good and forgot → Again; graded input becomes FSRS ratings 1–4, activating the Hard-penalty and Easy-bonus weights.",
                "Algorithm Settings offers target retention (85 / 90 / 95%), the scheduling goal, and interval fuzz — applied to day-scale intervals only; hour-scale steps are never fuzzed.",
                "Graduation is a horizon on stability, independent of the retention knob.",
                "The on-device parameter optimizer currently fits FSRS-6; FSRS-7 runs on its shipped defaults, which already behave like an optimized FSRS-4.5.",
            ]
        }
        return [.bullets(nil, specific + sharedAppLines)]
    }
}
