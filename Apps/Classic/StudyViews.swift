import SwiftUI
import VocabKit

/// Session start page: "Start with: Mix / All New / All Review".
struct StudyStartView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject var model: StudyModel

    var body: some View {
        Group {
            if model.session != nil {
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
                Text("📖")
                    .font(.system(size: 96))
                    .padding(.top, 60)
                Text(model.list.name)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                Text(model.sessionMessage)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)

                orderPicker
                    .padding(.top, 2)

                Text("Start with:")
                    .font(.headline.weight(.bold))
                    .padding(.top, 8)

                VStack(spacing: 14) {
                    ForEach(model.plans, id: \.mode) { plan in
                        planCard(plan)
                    }
                }
                .padding(.horizontal, 22)
                Color.clear.frame(height: 30)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("study.start")
        .onAppear { model.reloadPlans() }
    }

    /// Per-session recitation-order override (upgrade over the original).
    private var orderPicker: some View {
        HStack(spacing: 8) {
            Text("Order:")
                .foregroundStyle(.secondary)
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
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .font(.body.weight(.medium))
            }
            .accessibilityIdentifier("study.orderPicker")
        }
        .font(.body)
    }

    private func planCard(_ plan: SessionPlan) -> some View {
        Button {
            model.start(plan: plan)
        } label: {
            HStack(spacing: 18) {
                Text(plan.mode.rawValue)
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .center)
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
}

/// The flashcard screen.
struct FlashcardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
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

    private func card(for item: StudyItem) -> some View {
        let dictWord = model.currentDictWord()
        return VStack(spacing: 12) {
            Text(item.isNew ? "New Word" : "Review")
                .font(.body)
                .foregroundStyle(.secondary)

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
                            (Text("Note: ").bold() + Text(note))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .transition(.opacity)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ClassicTheme.cardBackground)
            )
            .padding(.horizontal, 22)
            .onTapGesture { withAnimation { model.reveal() } }
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Text("🎉")
                .font(.system(size: 80))
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

    private var bottomControls: some View {
        VStack(spacing: 0) {
            if let session = model.session, !session.isFinished {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(uiColor: .systemFill))
                        Rectangle()
                            .fill(ClassicTheme.wordChipBackground)
                            .frame(width: proxy.size.width * session.progress)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: max(4, proxy.size.width * session.progress), height: 4)
                    }
                }
                .frame(height: 4)
                .accessibilityIdentifier("study.progress")

                HStack(spacing: 14) {
                    Button {
                        answerTapped(false)
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

                    Button {
                        answerTapped(true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("I Know")
                        }
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ClassicTheme.knowButtonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(ClassicTheme.knowButtonBackground))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("study.know")
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.6))
    }

    /// First tap reveals the answer; the next tap commits it (so the user
    /// always sees the definition before moving on).
    @State private var pendingAnswer: Bool?

    private func answerTapped(_ knew: Bool) {
        if model.revealed {
            withAnimation { model.answer(pendingAnswer ?? knew) }
            pendingAnswer = nil
        } else {
            pendingAnswer = knew
            withAnimation { model.reveal() }
        }
    }
}
