# Roadmap: Beacon

## Overview

Beacon transforms from a simple task aggregator into an AI-powered work assistant that eliminates manual tracking. By reading work artifacts across email, Teams, Azure DevOps, and local files, the AI understands context and progress automatically, providing intelligent briefings and reducing the cognitive load of staying on top of work.

## Domain Expertise

- ~/.claude/skills/expertise/swift-macos/SKILL.md
- ~/.claude/skills/expertise/ai-llm/SKILL.md (if exists)

## Milestones

- ✅ **v1.0 MVP** - Phases 1-7 (shipped 2026-01-18)
- 🚧 **v1.1 AI-Powered Work Assistant** - Phases 8-17 (in progress)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

<details>
<summary>✅ v1.0 MVP (Phases 1-7) - SHIPPED 2026-01-18</summary>

### Phase 1: Project Setup
**Goal**: Initialize SwiftUI macOS menu bar app with basic structure
**Plans**: Completed

### Phase 2: Microsoft OAuth
**Goal**: Implement MSAL authentication for Microsoft services
**Plans**: Completed

### Phase 3: Azure DevOps Integration
**Goal**: Fetch work items assigned to current user
**Plans**: Completed

### Phase 4: Outlook Integration
**Goal**: Fetch flagged/important emails via Microsoft Graph
**Plans**: Completed

### Phase 5: Google OAuth & Gmail
**Goal**: Implement Google Sign-In and Gmail API integration
**Plans**: Completed

### Phase 6: Unified Task View
**Goal**: Combine all sources into unified, sortable task list
**Plans**: Completed

### Phase 7: Settings & Polish
**Goal**: Settings UI, keyboard shortcuts, Focus Mode awareness
**Plans**: Completed

**Stats:** 31 files, 3,483 LOC, 80 commits, 2 days

</details>

### 🚧 v1.1 AI-Powered Work Assistant (In Progress)

**Milestone Goal:** Transform Beacon from a task aggregator into an intelligent work assistant that eliminates manual tracking by using AI to automatically prioritize, track progress, and generate briefings.

#### Phase 8: AI Infrastructure ✅

**Goal**: Set up PostgreSQL + pgvector, Ollama integration, and OpenRouter connection
**Depends on**: v1.0 complete
**Completed**: 2026-01-19

Files created:
- Config/AIConfig.swift - Configuration for DB, Ollama, OpenRouter
- Services/AI/OllamaService.swift - Actor for local LLM (embed, chat, generate)
- Services/AI/OllamaModels.swift - Request/response models for Ollama API
- Services/AI/OpenRouterService.swift - Actor for cloud LLM (Keychain-based auth)
- Services/AI/OpenRouterModels.swift - Request/response models + models enum
- Services/Database/DatabaseService.swift - Actor for pgvector (stub for Phase 9)
- Services/Database/DatabaseModels.swift - BeaconItem, SearchResult models
- Services/AI/AIManager.swift - @MainActor orchestrator with TaskComplexity routing
- docker/docker-compose.yml - Documentation-only Docker setup
- docker/init/01-init-beacon.sql - Database schema with pgvector

Plans:
- [x] 08-01: PLAN.md (Database + Ollama + OpenRouter infrastructure)

#### Phase 9: Data Persistence Layer ✅

**Goal**: Store all fetched task/email data in database, create vector embeddings
**Depends on**: Phase 8
**Completed**: 2026-01-19

Files modified:
- Package.swift - Added PostgresNIO dependency (v1.21.0+)
- Services/Database/DatabaseService.swift - Full PostgresNIO implementation with CRUD, vector search
- Services/Database/DatabaseModels.swift - Conversion extensions (WorkItem, Email, UnifiedTask → BeaconItem)
- Services/AI/AIManager.swift - Persistence methods, embedding pipeline, search
- ViewModels/UnifiedTasksViewModel.swift - Auto-persistence after task fetch, background embedding

Plans:
- [x] 09-01: PLAN.md (PostgresNIO integration, data persistence, embedding flow)

#### Phase 10: Archive & Snooze

**Goal**: Make existing action buttons functional (Gmail archive, Outlook archive, ADO complete, local snooze)
**Depends on**: Phase 9

Files to modify:
- Services/Gmail/GmailService.swift - Add archiveMessage method
- Services/Outlook/OutlookService.swift - Add archiveMessage method
- Services/AzureDevOps/AzureDevOpsService.swift - Add completeWorkItem method
- Services/Database/DatabaseService.swift - Add snooze persistence methods
- ViewModels/UnifiedTasksViewModel.swift - Add action methods, filter snoozed
- Views/Tabs/TasksTab.swift - Wire up action handlers

Files to create:
- Models/SnoozedTask.swift - Snooze model and duration enum
- Views/Components/SnoozeSheet.swift - Snooze duration picker

Plans:
- [x] 10-01: PLAN.md (Archive & Snooze Actions - 10 tasks)

#### Phase 11: Teams Integration

**Goal**: Add Microsoft Teams as a data source for recent/urgent chat messages
**Depends on**: Phase 10
**Research**: Complete (Microsoft Graph Teams API, Chat.Read scope)
**Research findings**: No dedicated "saved messages" API - focusing on recent chats and urgent messages

Plans:
- [x] 11-01: PLAN.md (Teams API Infrastructure - 3 tasks)
- [x] 11-02: PLAN.md (Teams Data Integration - 3 tasks)
- [ ] 11-03: PLAN.md (Teams UI + Verification - 2 tasks)

#### Phase 12: Local File Scanner

**Goal**: Read GSD progress files and other local work artifacts
**Depends on**: Phase 11
**Research**: Complete (FileManager enumeration, Yams, git CLI)

Files created:
- Services/LocalScanner/LocalFileScannerModels.swift - Scanner models and config
- Services/LocalScanner/LocalFileScannerService.swift - Scanning actor

Plans:
- [x] 12-01: PLAN.md (Core Scanner Service - 7 tasks)
- [x] 12-02: PLAN.md (Database Integration - 5 tasks)
- [ ] 12-03: PLAN.md (UI Integration)

#### Phase 13: AI Priority Analysis

**Goal**: Background AI processing for automatic prioritization of tasks
**Depends on**: Phase 12
**Research**: Likely (LLM integration patterns, prompt engineering for priority classification)
**Research topics**: Priority inference prompts, batch processing patterns, Ollama vs OpenRouter selection logic
**Plans**: TBD

Plans:
- [ ] 13-01: TBD

#### Phase 14: Smart Progress Tracking

**Goal**: AI infers task progress by analyzing emails, commits, messages, and file changes
**Depends on**: Phase 13
**Research**: Likely (NLP patterns for progress inference, cross-source correlation)
**Research topics**: Progress indicators in email threads, commit message analysis, status inference from context
**Plans**: TBD

Plans:
- [ ] 14-01: TBD

#### Phase 15: Daily AI Briefing

**Goal**: AI-generated morning briefing summarizing priorities, deadlines, and focus areas
**Depends on**: Phase 14
**Research**: Unlikely (uses AI infrastructure from phases 8-9, internal prompt design)
**Plans**: TBD

Plans:
- [ ] 15-01: TBD

#### Phase 16: Desktop Notifications

**Goal**: Intelligent notifications when AI determines something is urgent
**Depends on**: Phase 15
**Research**: Unlikely (UserNotifications framework, established macOS patterns)
**Plans**: TBD

Plans:
- [ ] 16-01: TBD

#### Phase 17: Polish & Integration

**Goal**: Connect all AI features, refine UX, optimize performance
**Depends on**: Phase 16
**Research**: Unlikely (internal refinement, no new external integrations)
**Plans**: TBD

Plans:
- [ ] 17-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15 → 16 → 17

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1-7 | v1.0 MVP | - | Complete | 2026-01-18 |
| 8. AI Infrastructure | v1.1 | 1/1 | ✅ Complete | 2026-01-19 |
| 9. Data Persistence | v1.1 | 1/1 | ✅ Complete | 2026-01-19 |
| 10. Archive & Snooze | v1.1 | 1/1 | ✅ Complete | 2026-01-19 |
| 11. Teams Integration | v1.1 | 2/3 | 🚧 In Progress | - |
| 12. Local File Scanner | v1.1 | 2/3 | 🚧 In Progress | - |
| 13. AI Priority Analysis | v1.1 | 0/? | Not started | - |
| 14. Smart Progress Tracking | v1.1 | 0/? | Not started | - |
| 15. Daily AI Briefing | v1.1 | 0/? | Not started | - |
| 16. Desktop Notifications | v1.1 | 0/? | Not started | - |
| 17. Polish & Integration | v1.1 | 0/? | Not started | - |
