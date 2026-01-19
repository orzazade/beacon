# Project State: Beacon

## Current Position

Phase: 12 of 17 (Local File Scanner)
Plan: 1 of 3 in current phase
Status: In progress
Last activity: 2026-01-19 - Completed 12-01-PLAN.md

Progress: ███░░░░░░░ 38%

## Active Milestone

**v1.1 AI-Powered Work Assistant**
- Phases: 8-17 (10 phases)
- Completed: 3/10 (Phase 8 + Phase 9 + Phase 10)
- Planned: 1/10 (Phase 11 - in checkpoint)
- Focus: Transform from task aggregator to intelligent work assistant
- Key features: AI priority analysis, smart progress tracking, daily briefings

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

**Phase 11 Implementation (Teams Integration - Plan 01):**
- MicrosoftAuth.swift: Added Chat.Read to graphScopes
- TeamsModels.swift: 7 Codable models for Graph API responses
- TeamsService.swift: Actor with getRecentChats and getRecentMessages methods
- Filtering: urgent importance OR messages from last hour

**Phase 11 Implementation (Teams Integration - Plan 02):**
- TeamsMessage.swift: Model with full UnifiedTask protocol conformance
- UnifiedTask.swift: Added .teams case to TaskSource enum
- AuthManager.swift: teamsService property and getTeamsMessages method
- UnifiedTasksViewModel.swift: Teams fetch in loadAllTasks TaskGroup
- Updated all switch statements for TaskSource exhaustiveness

**Phase 11 Implementation (Teams Integration - Plan 03 - Partial):**
- UnifiedTask.swift: Reordered TaskSource cases (teams after outlook)
- Teams filter chip auto-included via CaseIterable + ForEach pattern

**Phase 12 Implementation (Local File Scanner - Plan 01):**
- Package.swift: Added Yams 6.0+ and swift-async-algorithms 1.0+
- LocalFileScannerModels.swift: LocalProject, CommitInfo, GSDDocument, LocalScannerConfig, LocalScannerError
- LocalFileScannerService.swift: Actor with complete scanning functionality
  - discoverGitRepositories: Lazy FileManager.enumerator with AsyncStream
  - extractFrontmatter: Yams-based YAML parsing
  - extractTicketCommits: Git CLI via Process with ticket regex
  - scanGSDDirectory/scanPhasesDirectory: GSD file discovery

## Pending Todos

- [ ] Test suite (deferred from v1.0, consider for v1.1)

## Blockers/Concerns

None - Phase 11 verified complete

## Roadmap Evolution

- v1.0 MVP shipped: 2026-01-18 (7 phases, 80 commits, 2 days)
- Milestone v1.1 created: AI-Powered Work Assistant, 10 phases (Phase 8-17)
- Phase 8 (AI Infrastructure) completed: 2026-01-19
- Phase 9 (Data Persistence) completed: 2026-01-19
- Phase 10 (Archive & Snooze) completed: 2026-01-19

## Session Continuity

Last session: 2026-01-19
Stopped at: Completed 12-01-PLAN.md
Resume file: None
Next: Execute 12-02-PLAN.md with /gsd:execute-phase 12
