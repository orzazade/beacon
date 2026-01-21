import SwiftUI

/// AI model selection section with per-feature pickers
/// Each feature (Briefings, Chat, Priority) has its own independent model selection
struct ModelSelectionSection: View {
    @ObservedObject private var briefingSettings = BriefingSettings.shared
    @ObservedObject private var chatSettings = ChatSettings.shared
    @ObservedObject private var prioritySettings = PrioritySettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Daily Briefings model picker
            FeatureModelPicker(
                title: "Daily Briefings",
                description: "AI-generated morning summary",
                selectedModel: $briefingSettings.selectedModel,
                availableModels: BriefingSettings.availableModels
            )

            Divider()

            // Chat Conversations model picker
            FeatureModelPicker(
                title: "Chat Conversations",
                description: "Conversational AI responses",
                selectedModel: $chatSettings.selectedModel,
                availableModels: ChatSettings.availableModels
            )

            Divider()

            // Priority Analysis model picker
            FeatureModelPicker(
                title: "Priority Analysis",
                description: "Task prioritization and scoring",
                selectedModel: $prioritySettings.selectedModel,
                availableModels: PrioritySettings.availableModels
            )
        }
    }
}

/// Reusable model picker component for a single feature
/// Shows title, description, and picker with model name and cost info
struct FeatureModelPicker: View {
    let title: String
    let description: String
    @Binding var selectedModel: OpenRouterModel
    let availableModels: [OpenRouterModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: $selectedModel) {
                ForEach(availableModels, id: \.self) { model in
                    HStack {
                        Text(model.displayName)
                        Spacer()
                        if model.isFree {
                            Text("FREE")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Text(formatCost(model))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(model)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// Format cost per million tokens for display
    private func formatCost(_ model: OpenRouterModel) -> String {
        let cost = model.inputCostPerMillion
        if cost < 1 {
            return String(format: "$%.2f/1M", cost)
        } else {
            return String(format: "$%.0f/1M", cost)
        }
    }
}

#Preview {
    ModelSelectionSection()
        .padding()
        .frame(width: 300)
}
