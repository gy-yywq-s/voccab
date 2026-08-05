import SwiftUI
import VocabKit

/// Session start — same zones (list identity, progress message, order,
/// "Start with" options) in the Passage language: bold sans headings with a
/// short rule, caption-over-value rows, native menu for the order override.
struct NeoStudyStartView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject var model: StudyModel

    var body: some View {
        Group {
            if model.session != nil {
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
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)

                orderRow
                    .padding(.top, 22)

                NeoSectionHeader(title: "Start with")
                    .padding(.top, 28)
                    .padding(.bottom, 2)

                VStack(spacing: 0) {
                    ForEach(Array(model.plans.enumerated()), id: \.element.mode) { index, plan in
                        planRow(plan)
                        if index < model.plans.count - 1 {
                            NeoHairline()
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("study.start")
        .onAppear { model.reloadPlans() }
    }

    /// Order override: label left, current value + chevrons right (native
    /// inline-value row, "Target reading pace" style).
    private var orderRow: some View {
        HStack {
            Text("Order")
                .font(.body)
            Spacer()
            Menu {
                ForEach(StudyOrder.allCases, id: \.self) { order in
                    Button {
                        model.order = order
                        model.reloadPlans()
                    } label: {
                        if model.order == order {
                            Label(order.label, systemImage: "checkmark")
                        } else {
                            Text(order.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.order.shortLabel)
                        .font(.body)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.7)
                )
            }
            .accessibilityIdentifier("study.orderPicker")
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            NeoHairline().offset(y: 12)
        }
    }

    private func planRow(_ plan: SessionPlan) -> some View {
        Button {
            model.start(plan: plan)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.mode.rawValue)
                        .font(Neo.rowTitle)
                        .foregroundStyle(.primary)
                    Text("\(plan.newCount) new · \(plan.reviewCount) review")
                        .font(Neo.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .opacity(plan.isEmpty ? 0.35 : 1)
        }
        .buttonStyle(NeoPressStyle())
        .disabled(plan.isEmpty)
        .accessibilityIdentifier("study.plan.\(plan.mode.rawValue)")
    }
}

/// Flashcard — same interaction contract (card, reveal, I Know / I Don't
/// Know, progress): white typed-surface card with light shadow, thin
/// progress line, red-text quiet decline + navy commit.
struct NeoFlashcardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingGrade: ReviewGrade?

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
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("study.flashcard")
        .onDisappear { model.pause() }
    }

    private var progressHeader: some View {
        Group {
            if let session = model.session, !session.isFinished {
                VStack(spacing: 6) {
                    HStack {
                        Text("\(session.position + 1) of \(session.totalCount)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(session.order.shortLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color(uiColor: .systemFill))
                            Rectangle()
                                .fill(Neo.blue)
                                .frame(width: max(3, proxy.size.width * session.progress))
                        }
                    }
                    .frame(height: 3)
                    .clipShape(Capsule())
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("study.progress")
                }
                .padding(.top, 8)
            }
        }
    }

    private func card(for item: StudyItem) -> some View {
        let dictWord = model.currentDictWord()
        return VStack(alignment: .leading, spacing: 0) {
            Text(item.isNew ? "New word" : "Review")
                .font(Neo.bodyFont)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Text(dictWord?.word ?? item.word)
                .font(.system(size: 34, weight: .bold))
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            HStack(spacing: 8) {
                if let phonetic = dictWord?.phonetic, !phonetic.isEmpty {
                    Text("/\(phonetic)/")
                        .font(Neo.bodyFont)
                        .foregroundStyle(.secondary)
                }
                Button {
                    model.speakCurrent()
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.subheadline)
                        .foregroundStyle(Neo.blue)
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
                    ForEach(dictWord?.translationLines ?? [], id: \.self) { line in
                        Text(line)
                            .font(Neo.bodyFont)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let note = model.currentState()?.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("note")
                                .font(Neo.caption)
                                .foregroundStyle(.secondary)
                            Text(Formatting.tidy(note))
                                .font(Neo.bodyFont)
                                .foregroundStyle(Neo.warm)
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { model.reveal() } }
    }

    private var finished: some View {
        VStack(spacing: 12) {
            Text("Session complete")
                .font(.title2.weight(.bold))
            let counts = env.userStore.todayCounts()
            Text("Today: \(counts.newWords) new · \(counts.reviewed) reviewed")
                .font(.body)
                .foregroundStyle(.secondary)
            NeoQuietButton(title: "Done", systemImage: "checkmark") {
                model.endSession()
                dismiss()
            }
            .padding(.top, 8)
        }
        .accessibilityIdentifier("study.finished")
    }

    private var bottomControls: some View {
        Group {
            if let session = model.session, !session.isFinished {
                VStack(spacing: 8) {
                    switch env.settings.answerStyle {
                    case .graded:
                        gradeRow
                    case .threeButtons:
                        triageRow
                    case .simple, .refine:
                        binaryRow
                        if env.settings.answerStyle == .refine, model.revealed {
                            refineRow
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private var binaryRow: some View {
        HStack(spacing: 12) {
            Button {
                answerTapped(.again)
            } label: {
                HStack {
                    Text("I Don't Know")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Image(systemName: "questionmark")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Neo.red)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Neo.red.opacity(0.08))
                )
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("study.dontKnow")

            Button {
                answerTapped(.good)
            } label: {
                HStack {
                    Text("I Know")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Neo.blue)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Neo.paleBlue)
                )
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("study.know")
        }
    }

    /// Optional post-reveal refinement in "Simple + refine" mode.
    private var refineRow: some View {
        HStack(spacing: 12) {
            Button("Knew it, barely — Hard") { answerTapped(.hard) }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Neo.warm)
                .accessibilityIdentifier("study.refineHard")
            Spacer()
            Button("Trivial — Easy") { answerTapped(.easy) }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("study.refineEasy")
        }
        .padding(.horizontal, 4)
    }

    private var gradeRow: some View {
        HStack(spacing: 8) {
            gradeButton(.again, tint: Neo.red, fill: Neo.red.opacity(0.08))
            gradeButton(.hard, tint: Neo.warm, fill: Neo.warm.opacity(0.10))
            gradeButton(.good, tint: Neo.blue, fill: Neo.paleBlue)
            gradeButton(.easy, tint: Color(red: 0.13, green: 0.5, blue: 0.42),
                        fill: Color(red: 0.13, green: 0.5, blue: 0.42).opacity(0.10))
        }
    }

    /// Three-button mode: the graded set minus Hard.
    private var triageRow: some View {
        HStack(spacing: 8) {
            gradeButton(.again, tint: Neo.red, fill: Neo.red.opacity(0.08))
            gradeButton(.good, tint: Neo.blue, fill: Neo.paleBlue)
            gradeButton(.easy, tint: Color(red: 0.13, green: 0.5, blue: 0.42),
                        fill: Color(red: 0.13, green: 0.5, blue: 0.42).opacity(0.10))
        }
    }

    private func gradeButton(_ grade: ReviewGrade, tint: Color, fill: Color) -> some View {
        Button {
            answerTapped(grade)
        } label: {
            Text(grade.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fill)
                )
        }
        .buttonStyle(NeoPressStyle())
        .accessibilityIdentifier("study.grade.\(grade.rawValue)")
    }

    private func answerTapped(_ grade: ReviewGrade) {
        if model.revealed {
            withAnimation { model.answer(grade: pendingGrade ?? grade) }
            pendingGrade = nil
        } else {
            pendingGrade = grade
            withAnimation { model.reveal() }
        }
    }
}
