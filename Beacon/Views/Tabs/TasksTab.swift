import SwiftUI
import AppKit

/// Tasks tab showing unified tasks from all sources (Azure DevOps, Outlook, Gmail)
struct TasksTab: View {
    @StateObject private var viewModel: UnifiedTasksViewModel
    @State private var showComingSoonAlert = false

    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: UnifiedTasksViewModel(authManager: authManager))
    }

    /// Whether detail view is showing (for animation)
    private var isShowingDetail: Bool {
        viewModel.selectedTask != nil
    }

    var body: some View {
        ZStack {
            // Task list view
            if viewModel.selectedTask == nil {
                Group {
                    if viewModel.isLoading && viewModel.tasks.isEmpty {
                        loadingView
                    } else if let error = viewModel.error, viewModel.tasks.isEmpty {
                        errorView(error)
                    } else if viewModel.tasks.isEmpty {
                        emptyView
                    } else {
                        taskListView
                    }
                }
                .transition(.move(edge: .leading))
            }

            // Detail view
            if let selectedTask = viewModel.selectedTask {
                TaskDetailView(
                    task: selectedTask,
                    onBack: { viewModel.clearSelection() },
                    onOpen: {
                        if let url = selectedTask.taskURL {
                            NSWorkspace.shared.open(url)
                        }
                        viewModel.clearSelection()
                    },
                    onArchive: {
                        // v1.0: Show coming soon alert
                        showComingSoonAlert = true
                    },
                    onSnooze: {
                        // v1.0: Show coming soon alert
                        showComingSoonAlert = true
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShowingDetail)
        .alert("Coming Soon", isPresented: $showComingSoonAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature will be available in a future update.")
        }
        .task {
            await viewModel.loadAllTasks()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading tasks...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await viewModel.loadAllTasks() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All caught up!")
                .font(.title3)
                .fontWeight(.semibold)

            Text("No tasks or flagged emails")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskListView: some View {
        VStack(spacing: 0) {
            // Filter chips
            FilterChips(
                selectedSources: $viewModel.selectedSources,
                selectedPriorities: $viewModel.selectedPriorities
            )
            .padding(.vertical, 8)

            // Task count
            HStack {
                Text("Showing \(viewModel.filteredTasks.count) of \(viewModel.tasks.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            Divider()

            // Task list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredTasks.indices, id: \.self) { index in
                        let task = viewModel.filteredTasks[index]
                        Button {
                            viewModel.selectTask(task)
                        } label: {
                            UnifiedTaskRow(task: task)
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.filteredTasks.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
}

#Preview {
    TasksTab(authManager: AuthManager())
        .frame(width: 320, height: 350)
}
