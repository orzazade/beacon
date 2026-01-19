---
phase: 10-archive-snooze
plan: 01
subsystem: actions, database, ui
tags: [swift, swiftui, gmail-api, graph-api, azure-devops-api, postgresql]

# Dependency graph
requires:
  - phase: 9-data-persistence
    provides: DatabaseService with PostgresNIO, AIManager with database integration
provides:
  - Gmail archive method (remove from INBOX)
  - Outlook archive method (move to Archive folder)
  - Azure DevOps complete method (update state to Closed)
  - SnoozedTask model with duration options
  - Database snooze persistence (store, retrieve, cleanup)
  - ViewModel action methods (archive, complete, snooze)
  - SnoozeSheet UI component
  - Functional action buttons in TaskDetailView
affects: [task-actions, email-management, work-item-management]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Pass-through methods in manager layers for service delegation
    - Local snooze with database persistence (no API required)
    - JSON Patch format for Azure DevOps updates

key-files:
  created:
    - Models/SnoozedTask.swift
    - Views/Components/SnoozeSheet.swift
  modified:
    - Services/Gmail/GmailService.swift
    - Services/Outlook/OutlookService.swift
    - Services/AzureDevOps/AzureDevOpsService.swift
    - Services/Database/DatabaseService.swift
    - ViewModels/UnifiedTasksViewModel.swift
    - Views/Tabs/TasksTab.swift
    - Auth/AuthManager.swift
    - Services/AI/AIManager.swift
    - docker/init/01-init-beacon.sql

key-decisions:
  - "Gmail archive removes INBOX label (message stays in All Mail)"
  - "Outlook archive uses well-known folder name 'archive'"
  - "ADO complete defaults to 'Closed' state (works for Agile/CMMI)"
  - "Snooze is local-only using PostgreSQL (no external API)"
  - "Snoozed tasks filtered from display until expiration"

patterns-established:
  - "Service methods for write operations follow same actor pattern as reads"
  - "Manager pass-through methods for service delegation"
  - "Database upsert with ON CONFLICT for snooze updates"

# Metrics
duration: 5min
completed: 2026-01-19
---

# Phase 10: Archive & Snooze Summary

**Gmail/Outlook archive, ADO complete, and local snooze with PostgreSQL persistence and SnoozeSheet UI**

## Performance

- **Duration:** 5 min
- **Started:** 2026-01-19T03:08:55Z
- **Completed:** 2026-01-19T03:13:57Z
- **Tasks:** 10 (Task 1 was pre-implemented)
- **Files modified:** 10

## Accomplishments
- Gmail archive removes messages from INBOX (stays in All Mail)
- Outlook archive moves messages to Archive folder via Graph API
- Azure DevOps complete updates work item state to "Closed"
- Local snooze with 1h, 3h, Tomorrow, Next Week duration options
- Snoozed tasks automatically filtered from display
- Action buttons now functional in TaskDetailView

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Gmail Archive Method** - Pre-existing (already in GmailService.swift)
2. **Task 2: Add Outlook Archive Method** - `c2525af`
3. **Task 3: Add Azure DevOps Complete Method** - `a1daabe`
4. **Task 4: Create SnoozedTask Model** - `e9748de`
5. **Task 5: Add Snooze Methods to DatabaseService** - `be0aaff`
6. **Task 6: Add Action Methods to ViewModel** - `9f8ccce`
7. **Task 9: Add AuthManager Pass-Through Methods** - `961a5b5`
8. **Task 10: Add AIManager Snooze Methods** - `a937887`
9. **Task 8: Create SnoozeSheet View** - `1ec7788`
10. **Task 7: Wire Up Actions in TasksTab** - `4cb6a37`

## Files Created/Modified
- `Models/SnoozedTask.swift` - Snooze model with duration enum
- `Views/Components/SnoozeSheet.swift` - Duration picker sheet
- `Services/Gmail/GmailService.swift` - archiveMessage method
- `Services/Outlook/OutlookService.swift` - archiveMessage method
- `Services/AzureDevOps/AzureDevOpsService.swift` - completeWorkItem method
- `Services/Database/DatabaseService.swift` - snooze CRUD operations
- `ViewModels/UnifiedTasksViewModel.swift` - action methods, snooze filtering
- `Views/Tabs/TasksTab.swift` - wired up actions, removed "Coming Soon"
- `Auth/AuthManager.swift` - pass-through for archive/complete
- `Services/AI/AIManager.swift` - pass-through for snooze ops
- `docker/init/01-init-beacon.sql` - snoozed_tasks table

## Decisions Made
- Gmail archive uses label removal (removeLabelIds: INBOX) per Gmail API docs
- Outlook uses well-known folder "archive" for move destination
- ADO defaults to "Closed" state which works for Agile and CMMI templates
- Snooze is entirely local - no API calls, just database persistence
- Task execution reordered to ensure dependencies compile (9, 10 before 7)

## Deviations from Plan

### Task Reordering
- **Reason:** Tasks 9 and 10 (AuthManager/AIManager pass-through) needed to be completed before Task 7 (wiring in TasksTab) to ensure compilation
- **Impact:** None - all tasks completed, just different order

### Task 1 Pre-existing
- **Found during:** Initial code review
- **Issue:** Gmail archiveMessage method already existed in GmailService.swift
- **Impact:** Skipped implementation, counted as complete

**Total deviations:** 2 minor (task reorder, pre-existing code)
**Impact on plan:** None - all functionality delivered as specified

## Issues Encountered
None - plan executed smoothly.

## User Setup Required
None - no external service configuration required.
Note: Snooze table needs to exist in database. Run docker-compose up to recreate, or manually execute the snoozed_tasks CREATE TABLE statement.

## Next Phase Readiness
- Archive/complete/snooze actions fully functional
- Ready for Phase 11: Keyboard Shortcuts
- Ready for Phase 12: Quick Add

---
*Phase: 10-archive-snooze*
*Completed: 2026-01-19*
