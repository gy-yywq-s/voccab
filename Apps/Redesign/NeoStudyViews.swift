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
                        .font(.largeTitle.weight(.bold))
                    Text(model.sessionMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
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
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(plan.newCount) new · \(plan.reviewCount) review")
                        .font(.subheadline)
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
    @State private var pendingAnswer: Bool?

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
        .background(Color(uiColor: .secondarySystemBackground))
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
        return VStack(spacing: 12) {
            Text(item.isNew ? "New word" : "Review")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(item.isNew ? Neo.warm : Neo.blue)

            VStack(spacing: 10) {
                Text(dictWord?.word ?? item.word)
                    .font(Neo.headword(40))
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    if let phonetic = dictWord?.phonetic, !phonetic.isEmpty {
                        Text("/\(phonetic)/")
                            .font(.body)
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

                if model.revealed {
                    VStack(alignment: .leading, spacing: 6) {
                        NeoHairline()
                            .padding(.vertical, 6)
                        ForEach(dictWord?.translationLines ?? [], id: \.self) { line in
                            Text(line)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let note = model.currentState()?.note, !note.isEmpty {
                            (Text("Note  ").font(.footnote.weight(.semibold)).foregroundColor(Neo.warm)
                                + Text(note).font(.footnote).foregroundColor(.secondary))
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
            )
            .padding(.horizontal, 20)
            .onTapGesture { withAnimation { model.reveal() } }
        }
    }

    private var finished: some View {
        VStack(spacing: 12) {
            Text("Session complete")
                .font(.title2.weight(.bold))
            let counts = env.userStore.todayCounts()
            Text("Today: \(counts.newWords) new · \(counts.reviewed) reviewed")
                .font(.body)
                .foregroundStyle(.secondary)
            NeoPrimaryButton(title: "Done") {
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
                HStack(spacing: 12) {
                    Button {
                        answerTapped(false)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark")
                                .font(.subheadline.weight(.semibold))
                            Text("I Don't Know")
                                .font(.body.weight(.medium))
                        }
                        .foregroundStyle(Neo.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Neo.red.opacity(0.09))
                        )
                    }
                    .buttonStyle(NeoPressStyle())
                    .accessibilityIdentifier("study.dontKnow")

                    Button {
                        answerTapped(true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                            Text("I Know")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Neo.navy)
                                .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                        )
                    }
                    .buttonStyle(NeoPressStyle())
                    .accessibilityIdentifier("study.know")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.regularMaterial)
            }
        }
    }

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
