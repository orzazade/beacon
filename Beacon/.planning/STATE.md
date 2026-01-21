# Project State: Beacon

## Current Position

Phase: 16 of 17 (Desktop Notifications) - IN PROGRESS
Plan: 2 of 3 in current phase (completed)
Status: Plan 16-02 complete - Pipeline integration ready
Last activity: 2026-01-21 - Completed Plan 16-02 (Trigger Integration with Pipelines)

Progress: █████████░ 93% (Phase 16 Plan 2 Complete)

## Active Milestone

**v1.1 AI-Powered Work Assistant**
- Phases: 8-17 (10 phases)
- Completed: 8/10 (Phase 8-15), Phase 16 Plan 2/3
- Next: Phase 16 Plan 3 (UI Integration)
- Focus: Transform from task aggregator to intelligent work assistant
- Key features: AI priority analysis, smart progress tracking, daily briefings, desktop notifications

## Accumulated Context

### Key Decisions

**v1.0 Decisions:**
- SwiftUI with MenuBarExtra for menu bar app
- Actor-based services for thread safety
- UnifiedTask protocol for mixed-source task lists
- Keychain for token storage (not UserDefaults)
- TaskGroup for parallel API fetching

**v1.1 Decisions:**
- Hybrid AI: Ollama (local) + OpenRouter (cloud)
- PostgreSQL + pgvector for vector storage
- Background AI processing (not on-demand)
- AI infers progress from context (no manual updates)

**Phase 9 Decisions:**
- Tuple-based row decoding for PostgresNIO performance
- Cast UUID/JSONB to text for reliable decoding
- Non-blocking persistence to avoid UI delays
- Background embedding in small batches (5 items at a time)
- Upsert by source+external_id for deduplication

**Phase 10 Decisions:**
- Gmail archive removes INBOX label (message stays in All Mail)
- Outlook archive uses well-known folder name "archive"
- ADO complete defaults to "Closed" state (works for Agile/CMMI)
- Snooze is local-only using PostgreSQL (no external API)
- Snoozed tasks filtered from display until expiration

**Phase 11 Decisions:**
- Teams message filtering: urgent importance OR from last hour
- Fetch last 24 hours of messages per chat
- Top 20 chats ordered by lastUpdatedDateTime
- Purple color for Teams source badge (distinct from blue ADO, teal Outlook, red Gmail)
- Teams messages use "message" item type in database
- Teams ordered after Outlook in filter chips (both Microsoft services)

**Phase 12 Decisions:**
- Store ticket IDs as comma-separated string in single metadata field
- Use project name from URL path for cleanup filtering via JSONB
- Batch embeddings in groups of 10 with 50ms delay
- Use AsyncTimerSequence for periodic scanning (clean async cancellation)
- Scanner state in AuthManager for @Published UI updates
- Initialize scanner only after database connection confirmed
- Settings use AppStorage for automatic UserDefaults sync

**Phase 13 Decisions:**
- P0-P4 priority levels (Critical, High, Medium, Low, Minimal)
- GPT-5.2 Nano as default model (best cost/quality at $0.10/$0.40 per million tokens)
- Batch processing of 10 items optimal for API efficiency
- Structured JSON outputs with strict schema for reliable parsing
- VIP emails normalized to lowercase for matching
- Age escalation formula: min(log2(days) * 0.05, 0.30)
- priority_analyzed_at column tracks re-processing needs
- DispatchSourceTimer for 30-minute background processing (menu bar app appropriate)
- Exponential backoff with jitter for rate limit handling
- 100k daily token limit (configurable)

**Phase 15 Decisions (Plan 15-01):**
- 4-hour default cache validity for briefings
- 15-minute minimum between manual refreshes (rate limiting)
- GPT-5.2 Nano default model (~$0.01/month at 1 briefing/day)
- Text-based JSON parsing for flexibility across models
- Fallback briefing when AI unavailable
- Parallel data aggregation for performance

**Phase 15 Decisions (Plan 15-02):**
- 5 section types: urgent (red), blocked (orange), stale (yellow), deadlines (blue), focus (purple)
- Source colors: azure_devops=blue, outlook=teal, gmail=red, teams=purple
- BriefingViewModel uses Combine to observe BriefingScheduler state
- Timer-based cooldown countdown for refresh rate limiting
- Navigation on item tap switches to Tasks tab (UIBR-03)

**Phase 15 Decisions (Plan 15-03):**
- Inline settings in popover (not separate navigation)
- Schedule time range 5-11 AM for morning briefing
- Auto-show Briefing tab before 10am when briefing generated
- Scheduler lifecycle managed through AIManager singleton
- Rate limiting feedback in settings UI

**Phase 16 Decisions (Plan 16-01):**
- P0/P1 delivered immediately, P2+ batched (20-min default)
- Hourly throttling with configurable max (default 10/hour)
- Per-source toggles for notification filtering
- UNUserNotificationCenter categories with Open/Snooze actions
- NotificationPriority.from(AIPriorityLevel) for priority conversion

**Phase 16 Decisions (Plan 16-02):**
- P0 notifications sent immediately via NotificationService.shared.notify()
- Stale notifications use .normal priority (batched, not urgent)
- Briefing uses .high priority (immediate but not P0 sound)
- Deadline notifications only for same-day items (daysRemaining == 0)
- AIManager starts notification service in checkServices() if enabled
- Pipeline callback pattern: detect event -> check settings -> create BeaconNotification -> notify()

### Technical Notes

**Architecture (v1.0):**
- 31 Swift files, 3,483 LOC
- Services: AzureDevOpsService, OutlookService, GmailService (actors)
- Auth: MicrosoftAuth, GoogleAuth (actors) via AuthManager
- Models: UnifiedTask protocol with WorkItem and Email conformance

**v1.1 Stack Additions:**
- PostgreSQL + pgvector (vector database)
- Ollama (local LLM)
- OpenRouter (cloud LLM routing)
- PostgresNIO (async Postgres client)

**Phase 8 Implementation (AI Infrastructure):**
- AIConfig.swift: Configuration for DB, Ollama, OpenRouter
- OllamaService.swift: Actor for local LLM (embed, chat, generate)
- OllamaModels.swift: Request/response models for Ollama API
- OpenRouterService.swift: Actor for cloud LLM (Keychain-based auth)
- OpenRouterModels.swift: Request/response models + available models enum
- DatabaseService.swift: Actor for pgvector (stub for Phase 9)
- DatabaseModels.swift: BeaconItem, SearchResult models
- AIManager.swift: @MainActor orchestrator with TaskComplexity routing
- Uses dev-stacks infrastructure (localhost:5432, localhost:11434)

**Phase 9 Implementation (Data Persistence):**
- Package.swift: Added PostgresNIO dependency (v1.21.0+)
- DatabaseService.swift: Full PostgresNIO implementation
  - Connection management with PostgresClient lifecycle
  - CRUD: storeItem (upsert), getItem (by ID/source+externalId)
  - Vector search using pgvector cosine similarity (<=> operator)
  - Bulk operations: storeItems, getItemsPendingEmbedding, getRecentItems
  - Statistics: getItemCounts, getPendingEmbeddingCount
- DatabaseModels.swift: Conversion extensions
  - BeaconItem.from(workItem/email/unifiedTask) converters
  - Array.toBeaconItems() for batch conversion
  - LocalizedError conformance for DatabaseError
- AIManager.swift: Persistence and embedding methods
  - storeItem/storeItems/storeTasks for persistence
  - processEmbeddings for batch embedding generation
  - searchSimilar for vector search queries
- UnifiedTasksViewModel.swift: Auto-persistence integration
  - Non-blocking persistence after loadAllTasks
  - Background embedding generation

**Phase 10 Implementation (Archive & Snooze):**
- GmailService.swift: archiveMessage method (removes INBOX label)
- OutlookService.swift: archiveMessage method (moves to Archive folder)
- AzureDevOpsService.swift: completeWorkItem method (JSON Patch to state)
- SnoozedTask.swift: Model with SnoozeDuration enum (1h, 3h, tomorrow, next week)
- DatabaseService.swift: Snooze CRUD (storeSnooze, getActiveSnoozedTaskIds, removeSnooze)
- UnifiedTasksViewModel.swift: Action methods and snooze filtering
- SnoozeSheet.swift: Duration picker UI component
- TasksTab.swift: Wired up archive/complete/snooze actions
- AuthManager.swift: Pass-through for archive/complete operations
- AIManager.swift: Pass-through for snooze operations
- snoozed_tasks table added to database schema

**Phase 11 Implementation (Teams Integration):**
- MicrosoftAuth.swift: Added Chat.Read to graphScopes
- TeamsModels.swift: 7 Codable models for Graph API responses
- TeamsService.swift: Actor with getRecentChats and getRecentMessages methods
- TeamsMessage.swift: Model with full UnifiedTask protocol conformance
- UnifiedTask.swift: Added .teams case to TaskSource enum (ordered after outlook)
- AuthManager.swift: teamsService property and getTeamsMessages method
- UnifiedTasksViewModel.swift: Teams fetch in loadAllTasks TaskGroup
- Filtering: urgent importance OR messages from last hour

**Phase 12 Implementation (Local File Scanner):**
- Package.swift: Added Yams 6.0+ and swift-async-algorithms 1.0+
- LocalFileScannerModels.swift: LocalProject, CommitInfo, GSDDocument, LocalScannerConfig, LocalScannerError
- LocalFileScannerService.swift: Actor with complete scanning functionality
  - discoverGitRepositories: Lazy FileManager.enumerator with AsyncStream
  - extractFrontmatter: Yams-based YAML parsing
  - extractTicketCommits: Git CLI via Process with ticket regex
  - scanGSDDirectory/scanPhasesDirectory: GSD file discovery
  - startPeriodicScanning/stopPeriodicScanning: AsyncTimerSequence-based periodic execution
- DatabaseModels.swift: BeaconItem.from(gsdDocument:) and from(commit:project:repoPath:) extensions
- DatabaseService.swift: markItemsInactive and getItems methods for local scanner
- AIManager.swift: getLocalItems, searchByTicketId, getCommitsForTicket, getGSDFilesForProject
- AuthManager.swift: localScanner property, initializeLocalScanner, triggerLocalScan, state tracking
- ContentView.swift: Scanner initialization on app appear, scan indicator in header
- SettingsView.swift: Local Scanner settings section (projects folder, interval, exclusions)
- TasksTab.swift: Refresh button triggers both API refresh and local scan

**Phase 13 Implementation (AI Priority Analysis - Complete):**
- AIPriority.swift: Priority models (AIPriorityLevel, PrioritySignal, PriorityScore, VIPContact, PriorityCostTracker)
- 02-priority-schema.sql: Database schema for priority scores, VIP contacts, cost tracking
- DatabaseModels.swift: BeaconItem extension with priority tracking helpers
- OpenRouterModels.swift: Structured output support (JSON Schema), GPT-5.2 Nano model, pricing
- PriorityAnalysisService.swift: Actor for batch priority analysis with structured outputs
- DatabaseService.swift: Priority score CRUD, VIP contact management, cost logging
- PriorityPipeline.swift: Background pipeline with DispatchSourceTimer, retry logic, daily limits
- AIManager.swift: Priority pipeline integration (start/stop/trigger, getPriorityScore, setManualPriority)
- PrioritySettings.swift: UserDefaults-backed settings singleton (daily limit, model, VIP emails, interval)
- PrioritySettingsViewModel.swift: @MainActor view model for settings UI
- VIPContactsEditor.swift: SwiftUI component for VIP contacts (list + bulk edit modes)
- PrioritySettingsView.swift: Complete settings UI (model, VIP, cost tracking, daily limit, pipeline status)
- PRIORITY_PIPELINE_INTEGRATION.md: Integration guide for UI team

**Phase 15 Implementation (Daily AI Briefing - Complete):**
Plan 15-01 (Models, Service, Scheduler):
- Briefing.swift: Models (BriefingContent, section items, BriefingInputData, BriefingError)
- 03-briefing-schema.sql: Database schema (beacon_briefings table, views, functions)
- BriefingSettings.swift: UserDefaults-backed settings singleton (schedule, cache, model, notifications)
- BriefingService.swift: Actor for data aggregation and AI generation
- BriefingScheduler.swift: @MainActor with DispatchSourceTimer for morning generation
- DatabaseService.swift: Briefing CRUD (storeBriefing, getLatestValidBriefing, aggregation queries)

Plan 15-02 (UI Components):
- BriefingSectionHeader.swift: Collapsible section headers with BriefingSectionType enum
  - 5 section types: urgent (red), blocked (orange), stale (yellow), deadlines (blue), focus (purple)
  - Count badge, animated chevron rotation, hover state
- BriefingItemRow.swift: Base row + 5 specialized variants
  - UrgentItemRow, BlockedItemRow, StaleItemRow, DeadlineItemRow, FocusAreaRow
  - Source colors: azure_devops=blue, outlook=teal, gmail=red, teams=purple
- BriefingViewModel.swift: @MainActor view model with Combine bindings to scheduler
  - loadBriefing(), refresh(), clearError() methods
  - Timer-based cooldown countdown for rate limiting
- BriefingTab.swift: Complete implementation replacing placeholder
  - 4 states: Loading, Error, Empty, Content
  - BriefingGreeting, BriefingClosingNote, BriefingFooter components
  - Navigation on item tap switches to Tasks tab (UIBR-03)

Plan 15-03 (Settings & Integration):
- AIManager.swift: Briefing integration (startBriefingScheduler, getCurrentBriefing, onBriefingGenerated)
- BriefingSettingsView.swift: Full settings UI (schedule, cache, model, status)
- ContentView.swift: BriefingSettingsSection inline component, scheduler initialization
- AppState.swift: Briefing callbacks, selectedItemId for navigation, auto-show tab before 10am

**Phase 16 Implementation (Desktop Notifications - In Progress):**
Plan 16-01 (Models, Settings, Core Service):
- Notification.swift: NotificationType enum, NotificationPriority with AIPriorityLevel conversion
- Notification.swift: BeaconNotification struct, NotificationBatch struct
- NotificationSettings.swift: UserDefaults-backed singleton (per-source toggles, priority threshold, snooze)
- NotificationService.swift: @MainActor singleton with DispatchSourceTimer batching
  - P0/P1 immediate delivery with distinct P0 sound
  - P2+ batched on 20-min interval (configurable)
  - Hourly throttling (10/hour default)
  - UNUserNotificationCenter categories with Open/Snooze actions
  - NotificationServiceStatistics for monitoring

Plan 16-02 (Pipeline Integration):
- PriorityPipeline.swift: Added onP0Detected callback, notification delivery for P0 items
- ProgressPipeline.swift: Added onTaskBecameStale callback, notifiedStaleIds tracking, clearStaleTracking
- BriefingScheduler.swift: Added sendBriefingNotificationViaService(), sendDeadlineNotifications()
- AIManager.swift: Added notificationService property, lifecycle methods, snooze controls, callbacks

## Pending Todos

- [ ] Test suite (deferred from v1.0, consider for v1.1)

## Blockers/Concerns

None - Phase 16 Plan 1 complete

## Roadmap Evolution

- v1.0 MVP shipped: 2026-01-18 (7 phases, 80 commits, 2 days)
- Milestone v1.1 created: AI-Powered Work Assistant, 10 phases (Phase 8-17)
- Phase 8 (AI Infrastructure) completed: 2026-01-19
- Phase 9 (Data Persistence) completed: 2026-01-19
- Phase 10 (Archive & Snooze) completed: 2026-01-19
- Phase 11 (Teams Integration) completed: 2026-01-19
- Phase 12 (Local File Scanner) completed: 2026-01-19
- Phase 13 Plan 1 (Priority Models) completed: 2026-01-20
- Phase 13 Plan 2 (Priority Analysis Service) completed: 2026-01-20
- Phase 13 Plan 3 (Background Priority Pipeline) completed: 2026-01-20
- Phase 13 Plan 4 (UI Integration) completed: 2026-01-20
- Phase 13 Plan 5 (Settings UI) completed: 2026-01-20
- Phase 13 (AI Priority Analysis) completed: 2026-01-20
- Phase 14 (Smart Progress Tracking) completed: 2026-01-20
- Phase 15 Plan 1 (Briefing Models, Service, Scheduler) completed: 2026-01-20
- Phase 15 Plan 2 (Briefing UI Components) completed: 2026-01-20
- Phase 15 Plan 3 (Settings and Integration) completed: 2026-01-20
- Phase 15 (Daily AI Briefing) completed: 2026-01-20
- Phase 16 Plan 1 (Notification Models, Settings, Core Service) completed: 2026-01-21
- Phase 16 Plan 2 (Pipeline Integration) completed: 2026-01-21

## Session Continuity

Last session: 2026-01-21
Stopped at: Completed Phase 16 Plan 2 (Trigger Integration with Pipelines)
Resume file: None
Next: Phase 16 Plan 3 (UI Integration)
