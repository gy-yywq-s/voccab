import SwiftUI
import VocabKit

/// Session start — same zones (list identity, progress message, order,
/// "Start with" options) with editorial treatment: serif list title, quiet
/// stats line, options as a grouped white field block with hairlines.
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Study")
                        .font(Neo.sans(13, weight: .semibold))
                        .kerning(1.1)
                        .foregroundStyle(Neo.faint)
                        .textCase(.uppercase)
                    Text(model.list.name)
                        .font(Neo.pageTitle)
                        .foregroundStyle(Neo.ink)
                    Text(model.sessionMessage)
                        .font(Neo.sans(15))
                        .foregroundStyle(Neo.graphite)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)

                orderRow
                    .padding(.top, 26)

                NeoSectionHeader(title: "Start With")
                    .padding(.top, 30)
                    .padding(.bottom, 10)

                VStack(spacing: 0) {
                    ForEach(Array(model.plans.enumerated()), id: \.element.mode) { index, plan in
                        planRow(plan)
                        if index < model.plans.count - 1 {
                            Rectangle().fill(Neo.hairline).frame(height: 0.5)
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Neo.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Neo.hairline, lineWidth: 0.8)
                        )
                )
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .background(Neo.paper)
        .accessibilityIdentifier("study.start")
        .onAppear { model.reloadPlans() }
    }

    /// Recitation-order override: compact row, label left, value+control right.
    private var orderRow: some View {
        HStack {
            Text("Order")
                .font(Neo.sans(15, weight: .medium))
                .foregroundStyle(Neo.ink)
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
                        .font(Neo.sans(15))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Neo.blue)
            }
            .accessibilityIdentifier("study.orderPicker")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Neo.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.8)
                )
        )
    }

    private func planRow(_ plan: SessionPlan) -> some View {
        Button {
            model.start(plan: plan)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.mode.rawValue)
                    .font(Neo.serif(19, weight: .semibold))
                    .foregroundStyle(Neo.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(plan.newCount) new")
                    Text("\(plan.reviewCount) review")
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Neo.graphite)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Neo.faint)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
            .opacity(plan.isEmpty ? 0.35 : 1)
        }
        .buttonStyle(NeoPressStyle())
        .disabled(plan.isEmpty)
        .accessibilityIdentifier("study.plan.\(plan.mode.rawValue)")
    }
}

/// Flashcard — same interaction contract (card, reveal, I Know / I Don't
/// Know, progress) on a paper page: white field card with hairline + light
/// shadow, thin progress rule, compact paired actions.
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
        .background(Neo.paper)
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
                            .foregroundStyle(Neo.faint)
                        Spacer()
                        Text(session.order.shortLabel)
                            .font(.footnote)
                            .foregroundStyle(Neo.faint)
                    }
                    .padding(.horizontal, 24)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Neo.hairline)
                            Rectangle()
                                .fill(Neo.blue)
                                .frame(width: max(3, proxy.size.width * session.progress))
                        }
                    }
                    .frame(height: 2)
                    .accessibilityIdentifier("study.progress")
                }
                .padding(.top, 8)
            }
        }
    }

    private func card(for item: StudyItem) -> some View {
        let dictWord = model.currentDictWord()
        return VStack(spacing: 14) {
            Text(item.isNew ? "New word" : "Review")
                .font(Neo.sans(13, weight: .semibold))
                .kerning(1.1)
                .textCase(.uppercase)
                .foregroundStyle(item.isNew ? Neo.warm : Neo.blue)

            VStack(spacing: 12) {
                Text(dictWord?.word ?? item.word)
                    .font(Neo.serif(40, weight: .semibold))
                    .foregroundStyle(Neo.ink)
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    if let phonetic = dictWord?.phonetic, !phonetic.isEmpty {
                        Text("/\(phonetic)/")
                            .font(Neo.sans(16))
                            .foregroundStyle(Neo.graphite)
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
                                .font(Neo.sans(16))
                                .foregroundStyle(Neo.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let note = model.currentState()?.note, !note.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Rectangle().fill(Neo.warm).frame(width: 2)
                                Text(note)
                                    .font(Neo.sans(14))
                                    .foregroundStyle(Neo.graphite)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Neo.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Neo.hairline, lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            )
            .padding(.horizontal, 24)
            .onTapGesture { withAnimation { model.reveal() } }
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Text("Session complete")
                .font(Neo.serif(26, weight: .semibold))
                .foregroundStyle(Neo.ink)
            let counts = env.userStore.todayCounts()
            Text("Today: \(counts.newWords) new · \(counts.reviewed) reviewed")
                .font(Neo.sans(15))
                .foregroundStyle(Neo.graphite)
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
                VStack(spacing: 0) {
                    NeoHairline()
                    HStack(spacing: 12) {
                        Button {
                            answerTapped(false)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark")
                                    .font(.subheadline.weight(.semibold))
                                Text("I Don't Know")
                                    .font(Neo.sans(16, weight: .medium))
                            }
                            .foregroundStyle(Neo.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Neo.red.opacity(0.08))
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
                                    .font(Neo.sans(16, weight: .semibold))
                            }
                            .foregroundStyle(Neo.navyFillText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Neo.navy)
                            )
                        }
                        .buttonStyle(NeoPressStyle())
                        .accessibilityIdentifier("study.know")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
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
