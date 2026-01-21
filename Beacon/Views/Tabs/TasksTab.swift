import SwiftUI
import AppKit

/// Tasks tab showing unified tasks from all sources (Azure DevOps, Outlook, Gmail, Teams)
struct TasksTab: View {
    @StateObject private var viewModel: UnifiedTasksViewModel
    @ObservedObject private var authManager: AuthManager
    @State private var showSnoozeSheet = false
    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var hasLoadedInitially = false

    init(authManager: AuthManager) {
        self.authManager = authManager
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
                        Task {
                            await handleArchiveOrComplete(selectedTask)
                        }
                    },
                    onSnooze: {
                        showSnoozeSheet = true
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShowingDetail)
        .sheet(isPresented: $showSnoozeSheet) {
            if let task = viewModel.selectedTask {
                SnoozeSheet(
                    task: task,
                    onSnooze: { duration in
                        Task {
                            await handleSnooze(task, duration: duration)
                        }
                    },
                    onCancel: {
                        showSnoozeSheet = false
                    }
                )
            }
        }
        .alert("Action Error", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task {
            // Only load once on first appear, then use manual refresh
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            await viewModel.loadAllTasks()
        }
        .onChange(of: authManager.isMicrosoftSignedIn) { _, isSignedIn in
            // Only auto-refresh on first sign-in, not on every tab switch
            if isSignedIn && !hasLoadedInitially {
                hasLoadedInitially = true
                Task { await viewModel.loadAllTasks() }
            }
        }
        .onChange(of: authManager.isGoogleSignedIn) { _, isSignedIn in
            // Only auto-refresh on first sign-in, not on every tab switch
            if isSignedIn && !hasLoadedInitially {
                hasLoadedInitially = true
                Task { await viewModel.loadAllTasks() }
            }
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

    // MARK: - Action Handlers

    private func handleArchiveOrComplete(_ task: any UnifiedTask) async {
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            if let workItem = task as? WorkItem {
                try await viewModel.completeWorkItem(workItem)
            } else if let email = task as? Email {
                try await viewModel.archiveEmail(email)
            }
            viewModel.clearSelection()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func handleSnooze(_ task: any UnifiedTask, duration: SnoozeDuration) async {
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await viewModel.snoozeTask(task, duration: duration)
            showSnoozeSheet = false
            viewModel.clearSelection()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Views

    private var taskListView: some View {
        VStack(spacing: 0) {
            // Filter chips with source, priority, and progress filters
            FilterChips(
                selectedSources: $viewModel.selectedSources,
                selectedPriorities: $viewModel.selectedPriorities,
                selectedProgressStates: $viewModel.selectedProgressStates
            )
            .padding(.vertical, 8)

            // Task count with refresh button
            HStack {
                Text("Showing \(viewModel.filteredTasks.count) of \(viewModel.tasks.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                // Refresh button - triggers both API refresh and local scan
                Button {
                    Task {
                        // Refresh API tasks
                        await viewModel.loadAllTasks()
                        // Also trigger local scan
                        authManager.triggerLocalScan()
                    }
                } label: {
                    if viewModel.isLoading || authManager.isLocalScanInProgress {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading || authManager.isLocalScanInProgress)
                .help("Refresh tasks and scan local projects")
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
