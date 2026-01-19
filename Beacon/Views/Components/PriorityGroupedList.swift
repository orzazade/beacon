import SwiftUI

/// Groups items by priority level with collapsible sections
struct PriorityGroupedList<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let priorityForItem: (Item) -> AIPriorityLevel?
    let content: (Item) -> Content

    @State private var expandedSections: Set<AIPriorityLevel> = Set(AIPriorityLevel.allCases)

    init(
        items: [Item],
        priorityForItem: @escaping (Item) -> AIPriorityLevel?,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.priorityForItem = priorityForItem
        self.content = content
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedItems, id: \.level) { group in
                    Section {
                        if expandedSections.contains(group.level) {
                            ForEach(group.items) { item in
                                content(item)
                            }
                        }
                    } header: {
                        PrioritySectionHeader(
                            level: group.level,
                            count: group.items.count,
                            isExpanded: expandedSections.contains(group.level),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedSections.contains(group.level) {
                                        expandedSections.remove(group.level)
                                    } else {
                                        expandedSections.insert(group.level)
                                    }
                                }
                            }
                        )
                    }
                }

                // Items without priority
                if !unprioritizedItems.isEmpty {
                    Section {
                        ForEach(unprioritizedItems) { item in
                            content(item)
                        }
                    } header: {
                        UnprioritizedSectionHeader(count: unprioritizedItems.count)
                    }
                }
            }
        }
    }

    /// Group items by priority level, sorted P0 first
    private var groupedItems: [(level: AIPriorityLevel, items: [Item])] {
        var groups: [AIPriorityLevel: [Item]] = [:]

        for item in items {
            if let priority = priorityForItem(item) {
                groups[priority, default: []].append(item)
            }
        }

        return AIPriorityLevel.allCases
            .filter { groups[$0] != nil }
            .map { (level: $0, items: groups[$0]!) }
    }

    /// Items without assigned priority
    private var unprioritizedItems: [Item] {
        items.filter { priorityForItem($0) == nil }
    }
}

// MARK: - Section Headers

struct PrioritySectionHeader: View {
    let level: AIPriorityLevel
    let count: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                PriorityBadge(level: level)

                Text(level.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .buttonStyle(.plain)
    }
}

struct UnprioritizedSectionHeader: View {
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text("Not Yet Analyzed")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Text("\(count)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Flat List Sorting

extension Array {
    /// Sort items by priority (P0 first, then P1, etc.)
    func sortedByPriority<P: Comparable>(
        _ priorityKeyPath: KeyPath<Element, P?>,
        ascending: Bool = true
    ) -> [Element] {
        sorted { lhs, rhs in
            guard let lhsPriority = lhs[keyPath: priorityKeyPath],
                  let rhsPriority = rhs[keyPath: priorityKeyPath] else {
                // Items without priority go last
                if lhs[keyPath: priorityKeyPath] == nil && rhs[keyPath: priorityKeyPath] != nil {
                    return false
                }
                if lhs[keyPath: priorityKeyPath] != nil && rhs[keyPath: priorityKeyPath] == nil {
                    return true
                }
                return false
            }
            return ascending ? lhsPriority < rhsPriority : lhsPriority > rhsPriority
        }
    }
}
