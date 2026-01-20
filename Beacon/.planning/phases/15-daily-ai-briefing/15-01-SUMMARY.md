# Plan 15-01 Summary: Briefing Models, Service, and Scheduler

**Completed:** 2026-01-20
**Commits:** 7

## What Was Built

### 1. Briefing.swift Models
- `BriefingContent`: Complete AI-generated briefing with all sections, expiration tracking
- `BriefingUrgentItem`, `BriefingBlockedItem`, `BriefingStaleItem`, `BriefingDeadlineItem`: Section items
- `BriefingInputData`: Aggregated data for prompt formatting with `formatForPrompt()` method
- `BriefingError`: Error enum for briefing operations
- `BriefingAIResponse`: Model for parsing AI structured JSON output

### 2. Database Schema (03-briefing-schema.sql)
- `beacon_briefings` table for caching generated briefings with expiration
- Views for briefing aggregation:
  - `beacon_briefing_priority_items`: P0-P2 items
  - `beacon_briefing_deadline_items`: Items with due dates in 7 days
  - `beacon_briefing_blocked_items`: Blocked progress state
  - `beacon_briefing_stale_items`: Stale items
- Functions:
  - `get_briefing_priority_items()`: Fetch priority items with filtering
  - `get_new_high_priority_items()`: Items added since last briefing
  - `get_latest_valid_briefing()`: Cache retrieval
  - `cleanup_old_briefings()`: Maintenance

### 3. BriefingSettings.swift
- UserDefaults-backed singleton settings:
  - `isEnabled`: Toggle briefing (default true)
  - `scheduledHour/scheduledMinute`: Generation time (default 7:00 AM)
  - `showNotification`: macOS notification (default true)
  - `autoShowTab`: Auto-switch to Briefing tab (default true)
  - `cacheValidityHours`: Cache duration (default 4 hours)
  - `selectedModel`: AI model (default GPT-5.2 Nano)
  - `minRefreshIntervalMinutes`: Rate limiting (default 15 min)
- Helper methods for next scheduled time and cost estimation

### 4. BriefingService.swift (Actor)
- `getCurrentBriefing()`: Return cached if valid, otherwise generate
- `refreshBriefing()`: Force generate with rate limiting
- `aggregateBriefingData()`: Fetch priority, blocked, stale, deadline items in parallel
- `generateFallbackBriefing()`: Simple briefing when AI unavailable
- System prompt for structured JSON output
- JSON parsing with markdown code block handling

### 5. BriefingScheduler.swift (@MainActor)
- DispatchSourceTimer-based scheduling (menu bar app pattern)
- `start()/stop()/restart()`: Lifecycle management
- `triggerNow()`: Immediate generation
- `getCurrentBriefing()/refreshBriefing()`: Delegate to service
- `calculateNextScheduledTime()`: Next occurrence of scheduled time
- `sendBriefingNotification()`: macOS notification when ready
- `BriefingSchedulerStatistics`: Status reporting

### 6. DatabaseService Extensions
- `storeBriefing()`: Store BriefingContent to beacon_briefings
- `getLatestValidBriefing()`: Get non-expired cached briefing
- `getLatestBriefingTime()`: Timestamp for "new since" detection
- `getItemsWithPriorityLevels()`: P0-P2 items for briefing
- `getItemsWithUpcomingDeadlines()`: Items with due dates
- `getNewHighPriorityItemsSince()`: New P0-P1 items since date
- `getItemsWithProgressState()`: Blocked/stale items by state
- Decoding helpers for composite query results

## Key Decisions

1. **4-hour default cache validity**: Briefing refreshes at scheduled time, stays valid for morning work session
2. **15-minute refresh rate limiting**: Prevents excessive API costs from manual refreshes
3. **GPT-5.2 Nano default model**: Best cost/quality ratio (~$0.01/month at 1 briefing/day)
4. **Text-based JSON parsing**: Flexibility across models, avoid structured output complexity
5. **Fallback briefing**: Always show something even if AI unavailable
6. **Parallel data aggregation**: Fetch all data types concurrently for performance

## Files Created/Modified

**New Files:**
- `Beacon/Models/Briefing.swift` (301 lines)
- `Beacon/docker/init/03-briefing-schema.sql` (209 lines)
- `Beacon/Services/Settings/BriefingSettings.swift` (184 lines)
- `Beacon/Services/Briefing/BriefingService.swift` (341 lines)
- `Beacon/Services/Briefing/BriefingScheduler.swift` (301 lines)

**Modified Files:**
- `Beacon/Services/Database/DatabaseService.swift` (+334 lines)

## Verification

- [x] All models are Codable and properly structured
- [x] BriefingContent has isExpired computed property
- [x] BriefingInputData has formatForPrompt() method
- [x] BriefingSettings uses singleton pattern with defaults
- [x] BriefingService aggregates data from database
- [x] BriefingScheduler uses DispatchSourceTimer pattern
- [x] Database methods for briefing queries work
- [x] Build succeeds

## Next Steps (Plan 15-02)

1. UI Components:
   - BriefingTab.swift (replace placeholder)
   - BriefingSectionHeader.swift
   - BriefingItemRow.swift
   - BriefingFooter.swift

2. Integration:
   - AIManager briefing methods
   - AppState default tab logic
   - Settings UI for briefing configuration
