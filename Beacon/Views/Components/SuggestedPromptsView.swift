import SwiftUI

// MARK: - Suggested Prompts View

/// Quick action prompts shown for new/empty conversations
struct SuggestedPromptsView: View {
    let onSelect: (String) -> Void

    /// Default prompts for common user queries
    private let prompts = [
        "What should I focus on today?",
        "Summarize my urgent tasks",
        "Help me prioritize my work"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick actions")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            ForEach(prompts, id: \.self) { prompt in
                Button(action: { onSelect(prompt) }) {
                    HStack {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                            .foregroundColor(.purple)
                        Text(prompt)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - Previews

#Preview("Suggested Prompts") {
    SuggestedPromptsView { prompt in
        print("Selected: \(prompt)")
    }
    .frame(width: 320)
    .padding()
}
