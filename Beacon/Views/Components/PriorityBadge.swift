import SwiftUI

/// Linear-style priority badge with color and label
/// Shows P0/P1/P2/P3/P4 with appropriate colors
struct PriorityBadge: View {
    let level: AIPriorityLevel
    let showLabel: Bool
    let isManualOverride: Bool

    init(level: AIPriorityLevel, showLabel: Bool = false, isManualOverride: Bool = false) {
        self.level = level
        self.showLabel = showLabel
        self.isManualOverride = isManualOverride
    }

    var body: some View {
        HStack(spacing: 4) {
            // Priority pill
            Text(level.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Optional label on hover
            if showLabel {
                Text(level.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Manual override indicator
            if isManualOverride {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var backgroundColor: Color {
        switch level {
        case .p0: return Color.red.opacity(0.15)
        case .p1: return Color.orange.opacity(0.15)
        case .p2: return Color.yellow.opacity(0.15)
        case .p3: return Color.blue.opacity(0.15)
        case .p4: return Color.gray.opacity(0.15)
        }
    }

    private var textColor: Color {
        switch level {
        case .p0: return Color.red
        case .p1: return Color.orange
        case .p2: return Color(red: 0.7, green: 0.6, blue: 0.0)  // Darker yellow for readability
        case .p3: return Color.blue
        case .p4: return Color.gray
        }
    }
}

// MARK: - Interactive Priority Badge

/// Priority badge with tap-to-change functionality
struct InteractivePriorityBadge: View {
    @Binding var level: AIPriorityLevel
    let isManualOverride: Bool
    let onOverride: (AIPriorityLevel) -> Void

    @State private var showingPicker = false

    var body: some View {
        PriorityBadge(level: level, isManualOverride: isManualOverride)
            .onTapGesture {
                showingPicker = true
            }
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                PriorityPicker(selectedLevel: $level, onSelect: { newLevel in
                    onOverride(newLevel)
                    showingPicker = false
                })
                .padding()
                .frame(width: 200)
            }
    }
}

// MARK: - Priority Picker

/// Picker for selecting priority level
struct PriorityPicker: View {
    @Binding var selectedLevel: AIPriorityLevel
    let onSelect: (AIPriorityLevel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set Priority")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(AIPriorityLevel.allCases, id: \.self) { level in
                Button(action: {
                    selectedLevel = level
                    onSelect(level)
                }) {
                    HStack {
                        PriorityBadge(level: level)
                        Text(level.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                        if level == selectedLevel {
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

// MARK: - Priority Reasoning Popover

/// Shows AI reasoning for priority decision
struct PriorityReasoningView: View {
    let score: PriorityScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                PriorityBadge(level: score.level, showLabel: true, isManualOverride: score.isManualOverride)
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

                ForEach(score.signals, id: \.type) { signal in
                    HStack {
                        signalIcon(for: signal.type)
                            .foregroundColor(signalColor(for: signal.type))
                        Text(signal.description)
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.0f%%", signal.weight * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Metadata
            Divider()

            HStack {
                Text("Analyzed: \(score.analyzedAt.formatted(date: .abbreviated, time: .shortened))")
                Spacer()
                Text(score.modelUsed)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300)
    }

    private func signalIcon(for type: PrioritySignalType) -> Image {
        switch type {
        case .deadline: return Image(systemName: "calendar.badge.exclamationmark")
        case .vipSender: return Image(systemName: "star.fill")
        case .urgencyKeyword: return Image(systemName: "exclamationmark.triangle")
        case .actionRequired: return Image(systemName: "hand.point.right")
        case .ageEscalation: return Image(systemName: "clock.arrow.circlepath")
        case .ambiguous: return Image(systemName: "questionmark.circle")
        }
    }

    private func signalColor(for type: PrioritySignalType) -> Color {
        switch type {
        case .deadline: return .red
        case .vipSender: return .yellow
        case .urgencyKeyword: return .orange
        case .actionRequired: return .blue
        case .ageEscalation: return .purple
        case .ambiguous: return .gray
        }
    }
}

// MARK: - Previews

#Preview("Priority Badges") {
    VStack(spacing: 20) {
        ForEach(AIPriorityLevel.allCases, id: \.self) { level in
            HStack {
                PriorityBadge(level: level)
                PriorityBadge(level: level, showLabel: true)
                PriorityBadge(level: level, isManualOverride: true)
            }
        }
    }
    .padding()
}
