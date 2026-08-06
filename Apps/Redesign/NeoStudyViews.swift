import SwiftUI
import VocabKit


/// Session start — same zones (list identity, progress message, order,
/// "Start with" options) in the grouped-card language: serif list title,
/// quiet greeting, a compact order row, and an uppercase micro-label over
/// one soft card holding the three mode rows with count chips. A paused
/// session no longer auto-resumes: it surfaces as a primary Resume bar with
/// quieter escape hatches grouped on the same card language beneath it.
struct NeoStudyStartView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject var model: StudyModel

    /// Whether the user explicitly entered the flashcards this visit; a
    /// paused session shows the Resume choice until then.
    @State private var entered = false
    @State private var showDiscardConfirm = false
    @State private var showEndConfirm = false
    @State private var showCustomize = false
    @State private var customNew = -1
    @State private var customReview = -1

    var body: some View {
        Group {
            if model.session != nil, entered {
                NeoFlashcardView(model: model)
            } else {
                startContent
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var startContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.list.name)
                        .font(Neo.pageTitle)
                    Text(model.sessionMessage)
                        .font(Neo.bodyFont)
                        .foregroundStyle(Neo.graphite)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)

                if let paused = model.session {
                    resumeSection(paused)
                        .padding(.top, 26)
                } else {
                    orderRow
                        .padding(.top, 22)

                    Text("Start with")
                        .font(Neo.sectionLabel)
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Neo.graphite)
                        .padding(.top, 28)
                        .padding(.bottom, 8)

                    // Zero card padding: the rows' own 12pt vertical padding
                    // then reads identically at the card edges and at the
                    // hairlines, so Mix's top and All Review's bottom match
                    // the internal rhythm instead of doubling it.
                    NeoCard(padding: 0) {
                        planList
                            .padding(.horizontal, 16)
                    }
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Neo.page)
        .accessibilityIdentifier("study.start")
        .onAppear { model.reloadPlans() }
        .confirmationDialog("Discard the paused session?",
                            isPresented: $showDiscardConfirm,
                            titleVisibility: .visible) {
            Button("Discard and choose a new practice", role: .destructive) {
                withAnimation { model.endSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Answered cards stay recorded.")
        }
        .confirmationDialog("End this session?",
                            isPresented: $showEndConfirm,
                            titleVisibility: .visible) {
            Button("End session", role: .destructive) {
                withAnimation { model.endSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Answered cards stay recorded.")
        }
    }

    // MARK: Paused-session zone

    private func resumeSection(_ paused: StudySession) -> some View {
        let left = max(0, paused.totalCount - paused.position)
        return VStack(alignment: .leading, spacing: 16) {
            NeoBeginBar(title: "Resume practice · \(left) of \(paused.totalCount) left",
                        systemImage: "play.fill") {
                entered = true
            }
            .accessibilityIdentifier("study.resume")

            NeoCard {
                Button {
                    showDiscardConfirm = true
                } label: {
                    HStack {
                        Text("Start a different practice")
                            .font(.body)
                            .foregroundStyle(Neo.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Neo.faint)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("study.startDifferent")

                NeoHairline()

                Button {
                    showEndConfirm = true
                } label: {
                    HStack {
                        Text("End session")
                            .font(.body)
                            .foregroundStyle(Neo.red)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("study.endPaused")
            }
        }
    }

    // MARK: Plan chooser

    /// Order override: quiet compact row above the plan card — secondary
    /// label left, current value + small chevron right (settings menuRow
    /// style, no chrome).
    private var orderRow: some View {
        HStack {
            Text("Order")
                .font(.body)
                .foregroundStyle(Neo.graphite)
            Spacer()
            Menu {
                ForEach(Array(StudyOrder.grouped.enumerated()), id: \.offset) { _, group in
                    Section(group.label) {
                        ForEach(group.options, id: \.self) { order in
                            Button {
                                model.order = order
                                model.reloadPlans()
                            } label: {
                                Label(order.label,
                                      systemImage: model.order == order ? "checkmark" : order.symbol)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.order.shortLabel)
                        .font(.body)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Neo.graphite)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("study.orderPicker")
        }
    }

    private var planList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.plans.enumerated()), id: \.element.mode) { index, plan in
                planRow(plan)
                if plan.mode == .mix, showCustomize {
                    customizePanel
                        .padding(.bottom, 12)
                }
                if index < model.plans.count - 1 {
                    NeoHairline()
                }
            }
        }
    }

    private func planSymbol(_ mode: StudyMode) -> String {
        switch mode {
        case .mix: return "square.stack.3d.up"
        case .allNew: return "sparkles"
        case .allReview: return "clock.arrow.circlepath"
        }
    }

    private func planRow(_ plan: SessionPlan) -> some View {
        HStack(spacing: 8) {
            Button {
                model.start(plan: plan)
                entered = true
            } label: {
                // Title and count chips share one line, centered vertically;
                // review counts wear green, new counts blue.
                HStack(spacing: 12) {
                    Image(systemName: planSymbol(plan.mode))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Neo.graphite)
                        .frame(width: 26)
                    Text(plan.mode.rawValue)
                        .font(Neo.rowTitle)
                        .foregroundStyle(Neo.ink)
                    NeoChip(text: "\(plan.newCount) new")
                    NeoChip(text: "\(plan.reviewCount) review", tint: Neo.green)
                    Spacer()
                    // The Mix row's width goes to Customize; only rows
                    // without a trailing control keep the nav chevron.
                    if plan.mode != .mix {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Neo.faint)
                    }
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
                .opacity(plan.isEmpty ? 0.35 : 1)
            }
            .buttonStyle(NeoPressStyle())
            .disabled(plan.isEmpty)
            .accessibilityIdentifier("study.plan.\(plan.mode.rawValue)")

            if plan.mode == .mix {
                Button {
                    if customNew < 0 {
                        customNew = env.settings.dailyGoalNew
                        customReview = env.settings.dailyGoalReview
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showCustomize.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Customize")
                            .font(Neo.caption.weight(.medium))
                        Image(systemName: showCustomize ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Neo.graphite)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("study.plan.customize")
            }
        }
    }

    /// Per-session Mix override: two steppers prefilled from the daily
    /// goals, absolute caps for this one session only.
    private var customizePanel: some View {
        VStack(spacing: 0) {
            customStepperRow(label: "New", value: $customNew)
            NeoHairline()
            customStepperRow(label: "Review", value: $customReview)

            Button {
                model.startCustomMix(newCount: customNew, reviewCount: customReview)
                entered = true
            } label: {
                Text("Start custom mix")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Neo.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Neo.paleBlue)
                    )
            }
            .buttonStyle(NeoPressStyle())
            .disabled(customNew + customReview <= 0)
            .opacity(customNew + customReview <= 0 ? 0.4 : 1)
            .accessibilityIdentifier("study.plan.customStart")
            .padding(.top, 12)

            Text("For this session only.")
                .font(.system(size: 12))
                .foregroundStyle(Neo.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Neo.page)
        )
    }

    private func customStepperRow(label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(Neo.bodyFont)
            Spacer()
            Text("\(value.wrappedValue)")
                .font(Neo.bodyFont.monospacedDigit())
                .foregroundStyle(Neo.ink)
            Stepper("", value: value, in: 0...200, step: 5)
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Flashcard

private struct NeoDetailTarget: Identifiable {
    let word: String
    var id: String { word }
}

private struct NeoSeedRecord {
    let word: String
    let text: String
}

/// Flashcard — pre-reveal choice locks a grade and flips the card; the
/// post-reveal state offers Continue + refinement instead of repeating the
/// same binary buttons. White typed surface, hairlines, pale tints.
struct NeoFlashcardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss

    /// True when the pre-reveal lock happened on the card currently shown;
    /// guards against a stale `initialChoice` after undo / session churn.
    @State private var choseThisCard = false
    @State private var rechooseOpen = false
    @State private var longPressFired = false
    @State private var easyFlash = false
    @State private var lastSeed: NeoSeedRecord?
    /// Rung locked on the seed slider before the control collapses; nil
    /// when nothing is mid-selection.
    @State private var seedTapSelection: Int?
    @State private var detailTarget: NeoDetailTarget?
    @State private var showEndConfirm = false

    private var style: AnswerStyle { env.settings.answerStyle }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Spacer()
            if let item = model.session?.current {
                card(for: item)
            } else {
                finished
            }
            Spacer()
            bottomControls
        }
        .frame(maxWidth: .infinity)
        .background(Neo.page)
        .accessibilityIdentifier("study.flashcard")
        .onDisappear { model.pause() }
        .onChange(of: model.session?.current?.word) {
            choseThisCard = false
            rechooseOpen = false
            longPressFired = false
            easyFlash = false
            seedTapSelection = nil
        }
        .sheet(item: $detailTarget) { target in
            NeoStudyDetailSheet(word: target.word)
        }
        .confirmationDialog("End this session?",
                            isPresented: $showEndConfirm,
                            titleVisibility: .visible) {
            Button("End session", role: .destructive) {
                model.endSession()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Answered cards stay recorded.")
        }
    }

    // MARK: Header

    private var progressHeader: some View {
        Group {
            if let session = model.session, !session.isFinished {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text("\(session.position + 1) of \(session.totalCount)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Neo.graphite)
                        Spacer()
                        Text(session.order.shortLabel)
                            .font(.footnote)
                            .foregroundStyle(Neo.graphite)
                        if model.canUndo, !model.revealed {
                            undoButton
                        }
                        sessionMenu
                    }
                    .padding(.horizontal, 20)
                    SegmentedProgressBar(completed: session.position,
                                         total: session.totalCount,
                                         tint: Neo.blue)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("study.progress")
                }
                .padding(.top, 8)
            }
        }
    }

    /// Compact bordered-circle undo, shown only pre-reveal (answers advance
    /// instantly, so this rides the next card's hint row).
    private var undoButton: some View {
        Button {
            withAnimation { model.undoLast() }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Neo.graphite)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Neo.hairline, lineWidth: 0.7))
        }
        .buttonStyle(NeoPressStyle())
        .accessibilityIdentifier("study.undo")
    }

    private var sessionMenu: some View {
        Menu {
            Button {
                dismiss()
            } label: {
                Label("Pause & exit", systemImage: "pause.circle")
            }
            Button(role: .destructive) {
                showEndConfirm = true
            } label: {
                Label("End session", systemImage: "xmark.circle")
            }
            .accessibilityIdentifier("study.endSession")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(Neo.graphite)
                .frame(width: 30, height: 30)
        }
        .accessibilityIdentifier("study.menu")
    }

    // MARK: Card

    private func card(for item: StudyItem) -> some View {
        let dictWord = model.currentDictWord()
        return VStack(alignment: .leading, spacing: 0) {
            Text(item.isNew ? "New word" : "Review")
                .font(Neo.bodyFont)
                .foregroundStyle(Neo.graphite)
                .frame(maxWidth: .infinity)

            Text(dictWord?.word ?? item.word)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            HStack(spacing: 8) {
                if let phonetic = dictWord?.phonetic, !phonetic.isEmpty {
                    Text("/\(phonetic)/")
                        .font(Neo.bodyFont)
                        .foregroundStyle(Neo.graphite)
                }
                Button {
                    model.speakCurrent()
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.subheadline)
                        .foregroundStyle(Neo.graphite)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(NeoPressStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)

            if model.revealed {
                VStack(alignment: .leading, spacing: 8) {
                    NeoHairline()
                        .padding(.vertical, 14)
                    ForEach(env.definitionLines(for: item.word, dictWord: dictWord), id: \.self) { line in
                        Text(line)
                            .font(Neo.bodyFont)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let note = model.currentState()?.note, !note.isEmpty {
                        // Same reading-first note treatment as the word page:
                        // tracked label + primary text on a quiet warm block.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTE")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.4)
                                .foregroundStyle(Neo.warm)
                            Text(Formatting.tidy(note))
                                .font(Neo.bodyFont)
                                .foregroundStyle(Neo.ink)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Neo.warm.opacity(0.09))
                        )
                        .padding(.top, 10)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .topTrailing) {
            if style == .swipe {
                openDetailButton(for: item)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { revealByTap() }
        .gesture(cardDrag(for: item))
    }

    /// Small book button in the card corner — swipe style only, where the
    /// swipe-down shortcut is taken by "Hard".
    private func openDetailButton(for item: StudyItem) -> some View {
        Button {
            detailTarget = NeoDetailTarget(word: item.word)
        } label: {
            Image(systemName: "book")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Neo.graphite)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Neo.hairline, lineWidth: 0.7))
        }
        .buttonStyle(NeoPressStyle())
        .accessibilityIdentifier("study.openDetail")
        .padding(6)
    }

    private func revealByTap() {
        guard !model.revealed else { return }
        choseThisCard = false
        withAnimation { model.reveal() }
    }

    /// Swipe style: ← Again · → Good · ↑ Easy · ↓ Hard (pre-reveal locks,
    /// post-reveal commits). Other styles: swipe DOWN opens the word page.
    private func cardDrag(for item: StudyItem) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if style == .swipe {
                    if abs(dx) > abs(dy), abs(dx) > 60 {
                        swipeAnswer(dx > 0 ? .good : .again)
                    } else if abs(dy) > abs(dx), abs(dy) > 60 {
                        swipeAnswer(dy < 0 ? .easy : .hard)
                    }
                } else if dy > 60, dy > abs(dx) {
                    detailTarget = NeoDetailTarget(word: item.word)
                }
            }
    }

    private func swipeAnswer(_ grade: ReviewGrade) {
        if model.revealed {
            commitTapped(grade)
        } else {
            chooseTapped(grade)
        }
    }

    // MARK: Finished

    private var finished: some View {
        VStack(spacing: 12) {
            Text("Session complete")
                .font(.system(.title2, design: .rounded).weight(.bold))
            let counts = env.userStore.todayCounts()
            Text("Today: \(counts.newWords) new · \(counts.reviewed) reviewed")
                .font(.body)
                .foregroundStyle(Neo.graphite)
            NeoQuietButton(title: "Done", systemImage: "checkmark") {
                model.endSession()
                dismiss()
            }
            .padding(.top, 8)
        }
        .accessibilityIdentifier("study.finished")
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        Group {
            if let session = model.session, !session.isFinished,
               let item = session.current {
                VStack(spacing: 10) {
                    if model.revealed {
                        postRevealControls
                    } else {
                        if item.isNew, !model.seededThisSession.contains(item.word) {
                            seedBar(for: item)
                        } else if let seed = lastSeed, seed.word == item.word {
                            seededCapsule(seed.text)
                        }
                        preRevealControls
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: Choice plumbing

    private func chooseTapped(_ grade: ReviewGrade) {
        guard !model.revealed else { return }
        choseThisCard = true
        withAnimation { model.choose(grade) }
    }

    private func commitTapped(_ grade: ReviewGrade? = nil) {
        rechooseOpen = false
        choseThisCard = false
        withAnimation { model.commit(grade) }
    }

    // MARK: Pre-reveal

    @ViewBuilder
    private var preRevealControls: some View {
        switch style {
        case .graded:
            gradeButtonRow([.again, .hard, .good, .easy], commit: false)
        case .threeButtons:
            gradeButtonRow([.again, .good, .easy], commit: false)
        case .swipe:
            swipeHintRow
        case .simple, .refine, .longPress, .timeImplicit:
            binaryRow
        }
    }

    private var binaryRow: some View {
        HStack(spacing: 12) {
            Button {
                chooseTapped(.again)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.medium))
                    Text("I Don't Know")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Neo.red)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Neo.red.opacity(0.08))
                )
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("study.dontKnow")

            knowButton
        }
    }

    private var knowButton: some View {
        Button {
            if longPressFired {
                longPressFired = false
                return
            }
            chooseTapped(.good)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: easyFlash ? "sparkles" : "checkmark")
                    .font(.subheadline.weight(.medium))
                Text(easyFlash ? "Easy" : "I Know")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(easyFlash ? Neo.green : Neo.blue)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(easyFlash ? Neo.green.opacity(0.12) : Neo.blue.opacity(0.08))
            )
        }
        .buttonStyle(NeoPressStyle())
        .accessibilityIdentifier("study.know")
        .simultaneousGesture(knowLongPress)
    }

    /// Long-press accelerator ("Simple + long-press"): holding I Know for a
    /// beat answers Easy — never on the miss side.
    private var knowLongPress: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .onEnded { _ in
                guard style == .longPress, !model.revealed, !longPressFired else { return }
                longPressFired = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeIn(duration: 0.12)) { easyFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    easyFlash = false
                    chooseTapped(.easy)
                }
            }
    }

    private var swipeHintRow: some View {
        HStack(spacing: 8) {
            swipeHintChip("arrow.left", "Again", Neo.red)
            swipeHintChip("arrow.right", "Good", .blue)
            swipeHintChip("arrow.up", "Easy", Neo.green)
            swipeHintChip("arrow.down", "Hard", Neo.warm)
        }
    }

    private func swipeHintChip(_ symbol: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(tint)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .overlay(Capsule().stroke(Neo.hairline, lineWidth: 0.7))
    }

    // MARK: Post-reveal

    @ViewBuilder
    private var postRevealControls: some View {
        let choice = choseThisCard ? model.initialChoice : nil
        if let choice {
            HStack {
                lockedCapsule(choice)
                Spacer()
                Button {
                    withAnimation { rechooseOpen.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.semibold))
                        Text("Change answer")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(Neo.graphite)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("study.rechoose")
            }
            .padding(.horizontal, 4)

            if rechooseOpen {
                rechooseRow
            } else if choice != .again, style.isBinaryBase {
                refineRow
            }

            continueButton(for: choice)
        } else {
            // Flipped by tapping the card: the honest post-reveal choice is
            // the style's grade set — never the binary pair again.
            honestGradeRow
        }
    }

    private func lockedCapsule(_ choice: ReviewGrade) -> some View {
        Text(lockedText(choice))
            .font(.footnote.weight(.medium))
            .foregroundStyle(Neo.graphite)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Neo.cardFill))
    }

    private func lockedText(_ choice: ReviewGrade) -> String {
        if style == .timeImplicit { return "Timed: \(choice.label)" }
        if style.isBinaryBase {
            switch choice {
            case .again: return "You said: I didn't know it"
            case .good: return "You said: I knew it"
            default: return "You said: \(choice.label)"
            }
        }
        return "You said: \(choice.label)"
    }

    private func continueButton(for choice: ReviewGrade) -> some View {
        Button {
            commitTapped()
        } label: {
            HStack {
                Text(choice == .again ? "Continue — I didn't know it" : "Continue")
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Neo.blue)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Neo.blue.opacity(0.08))
            )
        }
        .buttonStyle(NeoPressStyle())
        .accessibilityIdentifier("study.continue")
    }

    /// Quick refinement of a locked pass — binary-base styles only.
    private var refineRow: some View {
        HStack(spacing: 8) {
            Button {
                commitTapped(.hard)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "tortoise")
                        .font(.caption.weight(.medium))
                    Text("Hard — barely")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Neo.neutral)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Neo.neutral.opacity(0.12))
                )
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("study.refineHard")

            Button {
                commitTapped(.easy)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "hare")
                        .font(.caption.weight(.medium))
                    Text("Easy — trivial")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Neo.green)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Neo.green.opacity(0.10))
                )
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("study.refineEasy")
        }
    }

    /// The full 4-grade override, opened by "Change answer".
    private var rechooseRow: some View {
        HStack(spacing: 8) {
            ForEach(ReviewGrade.allCases, id: \.rawValue) { grade in
                let colors = gradeColors(grade)
                Button {
                    commitTapped(grade)
                } label: {
                    Text(grade.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(colors.fill)
                        )
                }
                .buttonStyle(NeoPressStyle())
            }
        }
    }

    @ViewBuilder
    private var honestGradeRow: some View {
        if style == .threeButtons {
            gradeButtonRow([.again, .good, .easy], commit: true)
        } else {
            gradeButtonRow([.again, .hard, .good, .easy], commit: true)
        }
    }

    // MARK: Grade buttons

    private func gradeButtonRow(_ grades: [ReviewGrade], commit: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(grades, id: \.rawValue) { grade in
                gradeButton(grade) {
                    if commit {
                        commitTapped(grade)
                    } else {
                        chooseTapped(grade)
                    }
                }
            }
        }
    }

    private func gradeButton(_ grade: ReviewGrade, action: @escaping () -> Void) -> some View {
        let colors = gradeColors(grade)
        return Button(action: action) {
            Text(grade.label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.tint)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colors.fill)
                )
        }
        .buttonStyle(NeoPressStyle())
        .accessibilityIdentifier("study.grade.\(grade.rawValue)")
    }

    private func gradeColors(_ grade: ReviewGrade) -> (tint: Color, fill: Color) {
        switch grade {
        case .again: return (Neo.red, Neo.red.opacity(0.08))
        // Hard is the burnt-gray neutral — gold stays reserved for notes.
        case .hard: return (Neo.neutral, Neo.neutral.opacity(0.12))
        case .good: return (Neo.blue, Neo.paleBlue)
        case .easy: return (Neo.green, Neo.green.opacity(0.13))
        }
    }

    // MARK: New-word seeding

    private static let seedLabels = ["Not at all", "Barely", "A little",
                                     "Somewhat", "Well", "Very well"]

    /// "How well do you know this word?" — a snap wheel on unseeded new
    /// cards: spin (or tap a row) to a rung; the wheel rests on 0. The
    /// settled rung gives the scheduler its head start (1–5), and
    /// "Not at all" opens the word page to learn it first.
    private func seedBar(for item: StudyItem) -> some View {
        VStack(spacing: 10) {
            Text("How well do you know this word?")
                .font(.footnote)
                .foregroundStyle(Neo.graphite)
            NeoSeedWheel { rung in
                seedTapped(rung, for: item)
            }
        }
        .transition(.scale(scale: 0.95, anchor: .bottom).combined(with: .opacity))
    }

    private func seedTapped(_ rung: Int, for item: StudyItem) {
        guard seedTapSelection == nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        seedTapSelection = rung
        // Let the thumb settle on the chosen detent for a beat, then collapse
        // the slider to its one-line caption with a single animated state
        // change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard model.session?.current?.word == item.word else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                model.seedCurrentNewWord(rung: rung)
                lastSeed = NeoSeedRecord(
                    word: item.word,
                    text: rung == 0 ? "Brand new — no head start"
                                    : "Seeded · \(Self.seedLabels[rung])")
            }
            if rung == 0 {
                detailTarget = NeoDetailTarget(word: item.word)
            }
        }
    }

    private func seededCapsule(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Neo.graphite)
        }
        .frame(maxWidth: .infinity)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

// MARK: - Seed slider

/// "How well?" snap wheel: a three-row drum resting on rung 0. Spinning
/// snaps row to row with a selection tick and commits the settled rung
/// after a short pause; tapping a row commits it immediately. Rows fade
/// and shrink toward the drum's edges; the center row sits on a pale-blue
/// lens. Feeds `select` — the same seeding path as every earlier control.
private struct NeoSeedWheel: View {
    /// Concise description beside each rung number, rung 0 first.
    private static let labels = ["Not at all", "Seen it", "Recognize it",
                                 "Know it", "Know it well", "Know it cold"]

    let select: (Int) -> Void

    @State private var centered: Int? = 0
    @State private var commitWork: DispatchWorkItem?

    private let rowHeight: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Neo.paleBlue)
                .frame(height: rowHeight)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(0...5, id: \.self) { rung in
                        row(rung)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $centered, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.vertical, rowHeight, for: .scrollContent)
            .frame(height: rowHeight * 3)
            .onChange(of: centered) { old, new in
                guard let new, old != nil, old != new else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                scheduleCommit(new)
            }
        }
        .frame(maxWidth: 240)
    }

    /// A spin settles for half a second before committing, so passing rows
    /// on the way to the one you want never fires the seed.
    private func scheduleCommit(_ rung: Int) {
        commitWork?.cancel()
        let work = DispatchWorkItem { select(rung) }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func row(_ rung: Int) -> some View {
        let active = centered == rung
        return Button {
            commitWork?.cancel()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                centered = rung
            }
            select(rung)
        } label: {
            HStack(spacing: 8) {
                Text("\(rung)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                Text(Self.labels[rung])
                    .font(.system(size: 14, weight: active ? .medium : .regular, design: .rounded))
            }
            .foregroundStyle(active ? Neo.ink : Neo.faint)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(rung)
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(1 - abs(phase.value) * 0.55)
                .scaleEffect(1 - abs(phase.value) * 0.12)
        }
        .accessibilityIdentifier("study.seed.\(rung)")
    }
}

/// Word page presented from the study flow: the pager wrapped in its own
/// NavigationStack (the flashcard isn't a path-based destination context).
private struct NeoStudyDetailSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    let word: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NeoWordDetailPager(word: word, context: [])
                .neoDestinations(env: env)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
