import SwiftUI

/// Placeholder view for the Chat tab
/// Provides an interface to chat with Claude for quick questions
struct ChatTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Chat")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Ask Claude anything")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ChatTab()
        .frame(width: 320, height: 350)
}
