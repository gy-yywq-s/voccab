import SwiftUI
import VocabKit

/// Session start page: "Start with: Mix / All New / All Review". A paused
/// session no longer auto-resumes — it shows a primary Resume button with
/// quieter options beneath it.
struct StudyStartView: View {
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
                FlashcardView(model: model)
            } else {
                startContent
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var startContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(ClassicTheme.studyButtonText)
                    .padding(.top, 64)
                Text(model.list.name)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                Text(model.sessionMessage)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)

                if let paused = model.session {
                    resumeSection(paused)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                } else {
                    orderPicker
                        .padding(.top, 2)

                    Text("Start with:")
                        .font(.headline.weight(.bold))
                        .padding(.top, 8)

                    VStack(spacing: 14) {
                        ForEach(model.plans, id: \.mode) { plan in
                            planCard(plan)
                            if plan.mode == .mix {
                                customizeToggle
                                if showCustomize {
                                    customizePanel
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                }
                Color.clear.frame(height: 30)
            }
        }
        .background(Color(uiColor: .systemBackground))
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
        return VStack(spacing: 12) {
            Button {
                entered = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("Resume practice · \(left) of \(paused.totalCount) left")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(ClassicTheme.continueButtonBackground))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("study.resume")

            Button("Start a different practice") {
                showDiscardConfirm = true
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("study.startDifferent")

            Button("End session", role: .destructive) {
                showEndConfirm = true
            }
            .font(.subheadline)
            .accessibilityIdentifier("study.endPaused")
        }
    }

    // MARK: Plan chooser

    /// Per-session recitation-order override (upgrade over the original).
    private var orderPicker: some View {
        HStack(spacing: 8) {
            Text("Order:")
                .foregroundStyle(.secondary)
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
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .font(.body.weight(.medium))
            }
            .accessibilityIdentifier("study.orderPicker")
        }
        .font(.body)
    }

    private func planSymbol(_ mode: StudyMode) -> String {
        switch mode {
        case .mix: return "square.stack.3d.up"
        case .allNew: return "sparkles"
        case .allReview: return "clock.arrow.circlepath"
        }
    }

    private func planCard(_ plan: SessionPlan) -> some View {
        Button {
            model.start(plan: plan)
            entered = true
        } label: {
            HStack(spacing: 16) {
                Image(systemName: planSymbol(plan.mode))
                    .font(.title2)
                    .foregroundStyle(ClassicTheme.studyButtonText)
                    .frame(width: 44)
                Text(plan.mode.rawValue)
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Words: \(plan.newCount)")
                    Text("Review Words: \(plan.reviewCount)")
                }
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .opacity(plan.isEmpty ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(plan.isEmpty)
        .accessibilityIdentifier("study.plan.\(plan.mode.rawValue)")
    }

    private var customizeToggle: some View {
        Button {
            if customNew < 0 {
                customNew = env.settings.dailyGoalNew
                customReview = env.settings.dailyGoalReview
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showCustomize.toggle()
            }
        } label: {
            Label("Customize Mix", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityIdentifier("study.plan.customize")
    }

    /// Per-session Mix override: two steppers prefilled from the daily
    /// goals, absolute caps for this one session only.
    private var customizePanel: some View {
        VStack(spacing: 10) {
            Stepper(value: $customNew, in: 0...200, step: 5) {
                HStack {
                    Text("New")
                    Spacer()
                    Text("\(customNew)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: $customReview, in: 0...200, step: 5) {
                HStack {
                    Text("Review")
                    Spacer()
                    Text("\(customReview)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                model.startCustomMix(newCount: customNew, reviewCount: customReview)
                entered = true
            } label: {
                Text("Start Custom Mix")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(customNew + customReview <= 0)
            .accessibilityIdentifier("study.plan.customStart")

            Text("For this session only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Flashcard

private struct ClassicDetailTarget: Identifiable {
    let word: String
    var id: String { word }
}

private struct ClassicSeedRecord {
    let word: String
    let text: String
}

/// The flashcard screen. Pre-reveal answers lock a grade and flip the card;
/// the post-reveal state offers Continue + refinement instead of repeating
/// the same buttons.
struct FlashcardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss

    /// True when the pre-reveal lock happened on the card currently shown;
    /// guards against a stale `initialChoice` after undo / session churn.
    @State private var choseThisCard = false
    @State private var rechooseOpen = false
    @State private var longPressFired = false
    @State private var easyFlash = false
    @State private var lastSeed: ClassicSeedRecord?
    @State private var detailTarget: ClassicDetailTarget?
    @State private var showEndConfirm = false

    private var style: AnswerStyle { env.settings.answerStyle }

    var body: some View {
        VStack(spacing: 0) {
            topRow
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
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("study.flashcard")
        .onDisappear { model.pause() }
        .onChange(of: model.session?.current?.word) {
            choseThisCard = false
            rechooseOpen = false
            longPressFired = false
            easyFlash = false
        }
        .sheet(item: $detailTarget) { target in
            ClassicStudyDetailSheet(word: target.word)
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

    /// Session menu row: pause & exit (the back behavior) and end session.
    @ViewBuilder
    private var topRow: some View {
        if let session = model.session, !session.isFinished {
            HStack {
                Text("\(session.position + 1) of \(session.totalCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
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
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityIdentifier("study.menu")
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)
        }
    }

    // MARK: Card

    private func card(for item: StudyItem) -> some View {
        let dictWord = model.currentDictWord()
        return VStack(spacing: 12) {
            badge(for: item)

            VStack(spacing: 10) {
                Text(dictWord?.word ?? item.word)
                    .font(ClassicTheme.serifWord(size: 44))
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let phonetic = dictWord?.phonetic, !phonetic.isEmpty {
                        Text("/\(phonetic)/")
                            .font(.title3)
                    }
                    Button {
                        model.speakCurrent()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                    }
                }

                if model.revealed {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(dictWord?.translationLines ?? [], id: \.self) { line in
                            Text(line)
                                .font(.title3)
                        }
                        if let note = model.currentState()?.note, !note.isEmpty {
                            // Same note treatment as the word page header card.
                            VStack(alignment: .leading, spacing: 5) {
                                Text("NOTE")
                                    .font(.caption.weight(.semibold))
                                    .tracking(1.2)
                                    .foregroundStyle(.secondary)
                                Text(Formatting.tidy(note))
                                    .font(.body)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(ClassicTheme.noteBackground)
                            )
                            .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ClassicTheme.cardBackground)
            )
            .overlay(alignment: .top) {
                // New cards get a tinted top stripe.
                if item.isNew {
                    UnevenRoundedRectangle(topLeadingRadius: 22,
                                           bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0,
                                           topTrailingRadius: 22,
                                           style: .continuous)
                        .fill(Color.blue.opacity(0.3))
                        .frame(height: 6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if style == .swipe {
                    openDetailButton(for: item)
                }
            }
            .padding(.horizontal, 22)
            .contentShape(Rectangle())
            .onTapGesture { revealByTap() }
            .gesture(cardDrag(for: item))
        }
    }

    @ViewBuilder
    private func badge(for item: StudyItem) -> some View {
        if item.isNew {
            Text("NEW")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.blue.opacity(0.12)))
                .accessibilityLabel("New Word")
        } else {
            Text("REVIEW")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                .accessibilityLabel("Review")
        }
    }

    /// Small book button in the card corner — swipe style only, where the
    /// swipe-down shortcut is taken by "Hard".
    private func openDetailButton(for item: StudyItem) -> some View {
        Button {
            detailTarget = ClassicDetailTarget(word: item.word)
        } label: {
            Image(systemName: "book")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(uiColor: .systemBackground).opacity(0.8)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("study.openDetail")
        .padding(10)
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
                    detailTarget = ClassicDetailTarget(word: item.word)
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
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(ClassicTheme.studyButtonText)
            Text("Session complete!")
                .font(.title2.weight(.bold))
            let counts = env.userStore.todayCounts()
            Text(Formatting.greetingMessage(newWords: counts.newWords, reviewed: counts.reviewed))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("Done") {
                model.endSession()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("study.finished")
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            if let session = model.session, !session.isFinished,
               let item = session.current {
                HStack(spacing: 10) {
                    SegmentedProgressBar(completed: session.position,
                                         total: session.totalCount,
                                         tint: Color.accentColor.opacity(0.85))
                        .accessibilityIdentifier("study.progress")
                    if model.canUndo, !model.revealed {
                        undoButton
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 4)

                VStack(spacing: 10) {
                    if model.revealed {
                        postRevealControls
                    } else {
                        if item.isNew, !model.seededThisSession.contains(item.word) {
                            seedPanel(for: item)
                        } else if let seed = lastSeed, seed.word == item.word {
                            seededCapsule(seed.text)
                        }
                        preRevealControls
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 10)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.6))
    }

    /// Compact bordered-circle undo, shown only pre-reveal (answers advance
    /// instantly, so this rides the next card's progress row).
    private var undoButton: some View {
        Button {
            withAnimation { model.undoLast() }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Circle().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("study.undo")
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
        HStack(spacing: 14) {
            Button {
                chooseTapped(.again)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                    Text("I Don't Know")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(ClassicTheme.dontKnowButtonText)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule().fill(ClassicTheme.dontKnowButtonBackground))
            }
            .buttonStyle(.plain)
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
            HStack(spacing: 8) {
                Image(systemName: easyFlash ? "sparkles" : "checkmark.circle.fill")
                Text(easyFlash ? "Easy" : "I Know")
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(easyFlash ? Color.green : ClassicTheme.knowButtonText)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule().fill(easyFlash ? Color.green.opacity(0.15)
                                         : ClassicTheme.knowButtonBackground)
            )
        }
        .buttonStyle(.plain)
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
            swipeHintChip("arrow.left", "Again", ClassicTheme.dontKnowButtonText)
            swipeHintChip("arrow.right", "Good", ClassicTheme.knowButtonText)
            swipeHintChip("arrow.up", "Easy", .green)
            swipeHintChip("arrow.down", "Hard", .orange)
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
        .overlay(Capsule().strokeBorder(Color(uiColor: .separator), lineWidth: 0.7))
    }

    // MARK: Post-reveal

    @ViewBuilder
    private var postRevealControls: some View {
        let choice = choseThisCard ? model.initialChoice : nil
        if let choice {
            HStack {
                lockedCapsule(choice)
                Spacer()
                Button("Change answer") {
                    withAnimation { rechooseOpen.toggle() }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
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
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
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
            HStack(spacing: 8) {
                Text(choice == .again ? "Continue — I didn't know it" : "Continue")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "arrow.right")
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(ClassicTheme.continueButtonBackground))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("study.continue")
    }

    /// Quick refinement of a locked pass — binary-base styles only.
    private var refineRow: some View {
        HStack(spacing: 10) {
            Button {
                commitTapped(.hard)
            } label: {
                Text("Hard — barely")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("study.refineHard")

            Button {
                commitTapped(.easy)
            } label: {
                Text("Easy — trivial")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            }
            .buttonStyle(.plain)
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
                        .background(Capsule().fill(colors.fill))
                }
                .buttonStyle(.plain)
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
        HStack(spacing: 10) {
            ForEach(grades, id: \.rawValue) { grade in
                classicGrade(grade) {
                    if commit {
                        commitTapped(grade)
                    } else {
                        chooseTapped(grade)
                    }
                }
            }
        }
    }

    private func classicGrade(_ grade: ReviewGrade, action: @escaping () -> Void) -> some View {
        let colors = gradeColors(grade)
        return Button(action: action) {
            Text(grade.label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(colors.tint)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule().fill(colors.fill))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("study.grade.\(grade.rawValue)")
    }

    private func gradeColors(_ grade: ReviewGrade) -> (tint: Color, fill: Color) {
        switch grade {
        case .again: return (ClassicTheme.dontKnowButtonText, ClassicTheme.dontKnowButtonBackground)
        case .hard: return (.orange, Color.orange.opacity(0.15))
        case .good: return (ClassicTheme.knowButtonText, ClassicTheme.knowButtonBackground)
        case .easy: return (.green, Color.green.opacity(0.15))
        }
    }

    // MARK: New-word seeding

    private static let seedLabels = ["Not at all", "Barely", "A little",
                                     "Somewhat", "Well", "Very well"]

    /// "How well do you know this word?" — the pale-blue seed panel on new
    /// cards. One tap gives the scheduler a head start (rung 1–5); "Not at
    /// all" opens the word page to learn it first.
    private func seedPanel(for item: StudyItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How well do you know this word?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.blue)
            seedPillRow(for: item, rungs: [0, 1, 2])
            seedPillRow(for: item, rungs: [3, 4, 5])
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
    }

    private func seedPillRow(for item: StudyItem, rungs: [Int]) -> some View {
        HStack(spacing: 8) {
            ForEach(rungs, id: \.self) { rung in
                Button {
                    seedTapped(rung, for: item)
                } label: {
                    Text(Self.seedLabels[rung])
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(rung == 0 ? Color.secondary : Color.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Capsule().fill(Color(uiColor: .systemBackground)))
                        .overlay(Capsule().strokeBorder(Color.blue.opacity(0.25), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("study.seed.\(rung)")
            }
        }
    }

    private func seedTapped(_ rung: Int, for item: StudyItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            model.seedCurrentNewWord(rung: rung)
            lastSeed = ClassicSeedRecord(
                word: item.word,
                text: rung == 0 ? "Brand new — no head start"
                                : "Seeded: \(Self.seedLabels[rung])")
        }
        if rung == 0 {
            detailTarget = ClassicDetailTarget(word: item.word)
        }
    }

    private func seededCapsule(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.blue.opacity(0.08)))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .frame(maxWidth: .infinity)
    }
}

/// Word page presented from the study flow: the pager wrapped in its own
/// NavigationStack (the flashcard isn't a path-based destination context).
private struct ClassicStudyDetailSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    let word: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WordDetailPager(word: word, context: [])
                .classicDestinations(env: env)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
