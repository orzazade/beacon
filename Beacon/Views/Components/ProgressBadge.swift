import SwiftUI

/// Linear-style progress badge with color and SF Symbol icon
/// Shows progress state: Not Started, In Progress, Blocked, Done, Stale
struct ProgressBadge: View {
    let state: ProgressState
    let showLabel: Bool
    let isManualOverride: Bool

    init(state: ProgressState, showLabel: Bool = false, isManualOverride: Bool = false) {
        self.state = state
        self.showLabel = showLabel
        self.isManualOverride = isManualOverride
    }

    var body: some View {
        HStack(spacing: 4) {
            // Progress icon and label pill
            HStack(spacing: 3) {
                Image(systemName: state.iconName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(iconColor)

                if showLabel {
                    Text(state.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(textColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Manual override indicator
            if isManualOverride {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .notStarted: return Color.gray.opacity(0.15)
        case .inProgress: return Color.blue.opacity(0.15)
        case .blocked: return Color.orange.opacity(0.15)
        case .done: return Color.green.opacity(0.15)
        case .stale: return Color.yellow.opacity(0.15)
        }
    }

    private var textColor: Color {
        switch state {
        case .notStarted: return Color.gray
        case .inProgress: return Color.blue
        case .blocked: return Color.orange
        case .done: return Color.green
        case .stale: return Color(red: 0.7, green: 0.6, blue: 0.0) // Darker yellow for readability
        }
    }

    private var iconColor: Color {
        textColor
    }
}

// MARK: - Interactive Progress Badge

/// Progress badge with tap-to-change functionality
struct InteractiveProgressBadge: View {
    @Binding var state: ProgressState
    let isManualOverride: Bool
    let onOverride: (ProgressState) -> Void

    @State private var showingPicker = false

    var body: some View {
        ProgressBadge(state: state, isManualOverride: isManualOverride)
            .onTapGesture {
                showingPicker = true
            }
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                ProgressPicker(selectedState: $state, onSelect: { newState in
                    onOverride(newState)
                    showingPicker = false
                })
                .padding()
                .frame(width: 200)
            }
    }
}

// MARK: - Progress Picker

/// Picker for selecting progress state
struct ProgressPicker: View {
    @Binding var selectedState: ProgressState
    let onSelect: (ProgressState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set Progress")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(ProgressState.allCases, id: \.self) { state in
                Button(action: {
                    selectedState = state
                    onSelect(state)
                }) {
                    HStack {
                        ProgressBadge(state: state)
                        Text(state.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                        if state == selectedState {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }

            Divider()

            Text("Manual override will persist until cleared")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Progress Reasoning Popover

/// Shows AI reasoning for progress state determination
struct ProgressReasoningView: View {
    let score: ProgressScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                ProgressBadge(state: score.state, showLabel: true, isManualOverride: score.isManualOverride)
                Spacer()
                Text("Confidence: \(Int(score.confidence * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Reasoning
            Text(score.reasoning)
                .font(.body)

            // Signals
            if !score.signals.isEmpty {
                Divider()

                Text("Detected Signals")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(Array(score.signals.prefix(5).enumerated()), id: \.offset) { _, signal in
                    HStack {
                        signalIcon(for: signal.type)
                            .foregroundColor(signalColor(for: signal.type))
                        Text(signal.description)
                            .font(.caption)
                            .lineLimit(2)
                        Spacer()
                        Text(String(format: "%.0f%%", signal.weight * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Last activity
            if let lastActivity = score.lastActivityAt {
                Divider()
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("Last activity: \(lastActivity.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Metadata
            Divider()

            HStack {
                Text("Analyzed: \(score.inferredAt.formatted(date: .abbreviated, time: .shortened))")
                Spacer()
                Text(score.modelUsed)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 320)
    }

    private func signalIcon(for type: ProgressScoreSignalType) -> Image {
        switch type {
        case .commitment: return Image(systemName: "hand.point.right")
        case .activity: return Image(systemName: "arrow.triangle.2.circlepath")
        case .blocker: return Image(systemName: "exclamationmark.octagon")
        case .completion: return Image(systemName: "checkmark.circle.fill")
        case .escalation: return Image(systemName: "bell.badge")
        }
    }

    private func signalColor(for type: ProgressScoreSignalType) -> Color {
        switch type {
        case .commitment: return .blue
        case .activity: return .teal
        case .blocker: return .orange
        case .completion: return .green
        case .escalation: return .red
        }
    }
}

// MARK: - Compact Progress Indicator

/// Small progress indicator for use in task rows (icon only)
struct CompactProgressIndicator: View {
    let state: ProgressState

    var body: some View {
        Image(systemName: state.iconName)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(state.color)
            .frame(width: 16, height: 16)
    }
}

// MARK: - Previews

#Preview("Progress Badges") {
    VStack(spacing: 20) {
        ForEach(ProgressState.allCases, id: \.self) { state in
            HStack(spacing: 16) {
                ProgressBadge(state: state)
                ProgressBadge(state: state, showLabel: true)
                ProgressBadge(state: state, isManualOverride: true)
                CompactProgressIndicator(state: state)
            }
        }
    }
    .padding()
}

#Preview("Progress Reasoning") {
    ProgressReasoningView(
        score: ProgressScore(
            itemId: UUID(),
            state: .inProgress,
            confidence: 0.85,
            reasoning: "Recent activity detected: commits and emails indicate active work",
            signals: [
                ProgressScoreSignal(type: .activity, weight: 0.25, source: "commit", description: "Pushed fix for login bug"),
                ProgressScoreSignal(type: .commitment, weight: 0.10, source: "email", description: "Will complete by EOD")
            ],
            lastActivityAt: Date().addingTimeInterval(-3600),
            modelUsed: "openai/gpt-5.2-nano"
        )
    )
}
