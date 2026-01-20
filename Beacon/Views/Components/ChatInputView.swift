import SwiftUI

// MARK: - Chat Input View

/// Text input field with send/stop buttons and character count for the chat interface
struct ChatInputView: View {
    @Binding var text: String
    let characterLimit: Int
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    /// Characters remaining before hitting the limit
    var remainingCharacters: Int {
        characterLimit - text.count
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                TextField("Ask anything...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .onSubmit {
                        if canSend { onSend() }
                    }

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Stop generation")
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canSend)
                    .help("Send message")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)

            // Character count (show when approaching limit)
            if remainingCharacters < 200 {
                Text("\(remainingCharacters) characters remaining")
                    .font(.caption2)
                    .foregroundColor(remainingCharacters < 50 ? .red : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Previews

#Preview("Empty Input") {
    ChatInputView(
        text: .constant(""),
        characterLimit: 2000,
        isStreaming: false,
        canSend: false,
        onSend: {},
        onStop: {}
    )
    .frame(width: 320)
}

#Preview("With Text") {
    ChatInputView(
        text: .constant("What should I focus on today?"),
        characterLimit: 2000,
        isStreaming: false,
        canSend: true,
        onSend: {},
        onStop: {}
    )
    .frame(width: 320)
}

#Preview("Streaming") {
    ChatInputView(
        text: .constant(""),
        characterLimit: 2000,
        isStreaming: true,
        canSend: false,
        onSend: {},
        onStop: {}
    )
    .frame(width: 320)
}

#Preview("Near Character Limit") {
    ChatInputView(
        text: .constant(String(repeating: "a", count: 1900)),
        characterLimit: 2000,
        isStreaming: false,
        canSend: true,
        onSend: {},
        onStop: {}
    )
    .frame(width: 320)
}
