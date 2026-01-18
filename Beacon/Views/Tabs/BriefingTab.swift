import SwiftUI

/// Placeholder view for the Briefing tab
/// Shows the morning briefing with aggregated notifications and priorities
struct BriefingTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sun.horizon")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Briefing")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your daily overview will appear here")
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
    BriefingTab()
        .frame(width: 320, height: 350)
}
