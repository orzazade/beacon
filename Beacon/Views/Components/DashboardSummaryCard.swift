import SwiftUI

/// Summary card showing a count with icon and tap action
struct DashboardSummaryCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(count)")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundColor(count > 0 ? color : .secondary)

                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(count > 0 ? color.opacity(0.1) : Color.gray.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal row of summary cards
struct DashboardSummaryRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onNavigate: (DashboardFilter) -> Void

    var body: some View {
        HStack(spacing: 8) {
            DashboardSummaryCard(
                title: "Critical",
                count: viewModel.p0Count,
                icon: "exclamationmark.triangle.fill",
                color: .red
            ) {
                onNavigate(.critical)
            }

            DashboardSummaryCard(
                title: "Stale",
                count: viewModel.staleCount,
                icon: "clock.badge.exclamationmark",
                color: .orange
            ) {
                onNavigate(.stale)
            }

            DashboardSummaryCard(
                title: "In Progress",
                count: viewModel.inProgressCount,
                icon: "arrow.triangle.2.circlepath",
                color: .blue
            ) {
                onNavigate(.inProgress)
            }

            DashboardSummaryCard(
                title: "Pending",
                count: viewModel.pendingCount,
                icon: "tray.full",
                color: .purple
            ) {
                onNavigate(.pending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Filter types for dashboard navigation
enum DashboardFilter {
    case critical   // P0 items
    case stale      // Items with stale progress
    case inProgress // Items in_progress state
    case pending    // Items not_started state
}

// MARK: - Previews

#Preview("Dashboard Summary Row") {
    let viewModel = DashboardViewModel()
    return VStack {
        DashboardSummaryRow(viewModel: viewModel) { filter in
            print("Navigate to: \(filter)")
        }
    }
    .frame(width: 360)
}

#Preview("Dashboard Summary Cards") {
    HStack(spacing: 8) {
        DashboardSummaryCard(
            title: "Critical",
            count: 3,
            icon: "exclamationmark.triangle.fill",
            color: .red
        ) {}

        DashboardSummaryCard(
            title: "Stale",
            count: 0,
            icon: "clock.badge.exclamationmark",
            color: .orange
        ) {}

        DashboardSummaryCard(
            title: "In Progress",
            count: 7,
            icon: "arrow.triangle.2.circlepath",
            color: .blue
        ) {}

        DashboardSummaryCard(
            title: "Pending",
            count: 12,
            icon: "tray.full",
            color: .purple
        ) {}
    }
    .padding()
    .frame(width: 360)
}
