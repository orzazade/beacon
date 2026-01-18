import SwiftUI

/// A single filter chip button
struct FilterChip<T: Hashable>: View {
    let item: T
    let label: String
    let icon: String?
    let color: Color?
    let isSelected: Bool
    let action: () -> Void

    init(
        item: T,
        label: String,
        icon: String? = nil,
        color: Color? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.label = label
        self.icon = icon
        self.color = color
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                if let color = color {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal scrolling row of source filter chips
struct SourceFilterChips: View {
    @Binding var selectedSources: Set<TaskSource>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TaskSource.allCases, id: \.self) { source in
                    FilterChip(
                        item: source,
                        label: source.rawValue,
                        icon: source.icon,
                        isSelected: isSelected(source),
                        action: { toggle(source) }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
    }

    /// Empty selection means "show all"
    private func isSelected(_ source: TaskSource) -> Bool {
        selectedSources.isEmpty || selectedSources.contains(source)
    }

    private func toggle(_ source: TaskSource) {
        if selectedSources.isEmpty {
            // First selection: select only this one (unselect others)
            selectedSources = [source]
        } else if selectedSources.contains(source) {
            selectedSources.remove(source)
            // If removing last selection, return to "show all" state
            // Empty set is handled by isSelected returning true for all
        } else {
            selectedSources.insert(source)
            // If all are selected, clear to "show all" state
            if selectedSources.count == TaskSource.allCases.count {
                selectedSources.removeAll()
            }
        }
    }
}

/// Horizontal scrolling row of priority filter chips
struct PriorityFilterChips: View {
    @Binding var selectedPriorities: Set<TaskPriority>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    FilterChip(
                        item: priority,
                        label: priority.rawValue,
                        color: priority.color,
                        isSelected: isSelected(priority),
                        action: { toggle(priority) }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
    }

    /// Empty selection means "show all"
    private func isSelected(_ priority: TaskPriority) -> Bool {
        selectedPriorities.isEmpty || selectedPriorities.contains(priority)
    }

    private func toggle(_ priority: TaskPriority) {
        if selectedPriorities.isEmpty {
            // First selection: select only this one
            selectedPriorities = [priority]
        } else if selectedPriorities.contains(priority) {
            selectedPriorities.remove(priority)
        } else {
            selectedPriorities.insert(priority)
            // If all are selected, clear to "show all" state
            if selectedPriorities.count == TaskPriority.allCases.count {
                selectedPriorities.removeAll()
            }
        }
    }
}

/// Combined filter chips view with source and priority rows
struct FilterChips: View {
    @Binding var selectedSources: Set<TaskSource>
    @Binding var selectedPriorities: Set<TaskPriority>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SourceFilterChips(selectedSources: $selectedSources)
            PriorityFilterChips(selectedPriorities: $selectedPriorities)
        }
    }
}

// MARK: - Previews

#Preview("FilterChips") {
    struct PreviewWrapper: View {
        @State private var selectedSources: Set<TaskSource> = []
        @State private var selectedPriorities: Set<TaskPriority> = []

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Source Filters")
                    .font(.headline)
                SourceFilterChips(selectedSources: $selectedSources)

                Divider()

                Text("Priority Filters")
                    .font(.headline)
                PriorityFilterChips(selectedPriorities: $selectedPriorities)

                Divider()

                Text("Combined")
                    .font(.headline)
                FilterChips(
                    selectedSources: $selectedSources,
                    selectedPriorities: $selectedPriorities
                )

                Spacer()

                // Debug info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Sources: \(selectedSources.isEmpty ? "All" : selectedSources.map(\.rawValue).joined(separator: ", "))")
                        .font(.caption)
                    Text("Selected Priorities: \(selectedPriorities.isEmpty ? "All" : selectedPriorities.map(\.rawValue).joined(separator: ", "))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 320, height: 300)
        }
    }

    return PreviewWrapper()
}

#Preview("Single Chip") {
    HStack(spacing: 8) {
        FilterChip(
            item: TaskSource.azureDevOps,
            label: "Azure DevOps",
            icon: "ladybug.fill",
            isSelected: false,
            action: {}
        )
        FilterChip(
            item: TaskSource.outlook,
            label: "Outlook",
            icon: "envelope.fill",
            isSelected: true,
            action: {}
        )
        FilterChip(
            item: TaskPriority.urgent,
            label: "Urgent",
            color: .red,
            isSelected: false,
            action: {}
        )
        FilterChip(
            item: TaskPriority.high,
            label: "High",
            color: .orange,
            isSelected: true,
            action: {}
        )
    }
    .padding()
}
