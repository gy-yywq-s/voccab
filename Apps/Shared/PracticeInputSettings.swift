import SwiftUI
import VocabKit

/// Settings subpage: how the flashcard collects answers, how words graduate,
/// and what gets recorded — with per-algorithm adaptation spelled out so
/// nothing is a black box.
struct PracticeInputPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var answerStyle: AnswerStyle = .simple
    @State private var graduation: GraduationPolicy = .byAlgorithm
    @State private var recordExtended = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Answer style", topPadding: 8)
                ForEach(AnswerStyle.allCases, id: \.self) { style in
                    choiceRow(
                        title: style.label, subtitle: style.summary,
                        selected: answerStyle == style
                    ) {
                        answerStyle = style
                        env.settings.answerStyle = style
                    }
                }

                Text("How each algorithm uses grades")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 18)
                ForEach(SchedulerKind.allCases, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.label)
                            .font(.footnote.weight(.semibold))
                        Text(kind.gradeSupport)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                Text("The algorithm's own difficulty estimate (FSRS) keeps working alongside your grades: your grade is the input, its difficulty is what it learns from that input — they never conflict.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                sectionTitle("Graduation", topPadding: 26)
                ForEach(GraduationPolicy.allCases, id: \.self) { policy in
                    choiceRow(
                        title: policy.label, subtitle: policy.summary,
                        selected: graduation == policy
                    ) {
                        graduation = policy
                        env.settings.graduationPolicy = policy
                        env.touch()
                    }
                }

                sectionTitle("Data recording", topPadding: 26)
                Toggle(isOn: Binding(
                    get: { recordExtended },
                    set: { on in
                        recordExtended = on
                        env.settings.recordExtendedData = on
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Record detailed review data")
                            .font(.body)
                        Text("Grade, response time, and interval context with every review — stays on this device, powers future per-word tuning, and exports with your data.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Practice Input")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            answerStyle = env.settings.answerStyle
            graduation = env.settings.graduationPolicy
            recordExtended = env.settings.recordExtendedData
        }
    }

    private func sectionTitle(_ title: String, topPadding: CGFloat) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .padding(.top, topPadding)
            .padding(.bottom, 6)
    }

    private func choiceRow(title: String, subtitle: String, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
