# Priority Pipeline Integration Notes

## Startup Integration

The priority pipeline should be started when:
1. The app launches AND
2. OpenRouter API key is configured

Add to your app initialization (e.g., `BeaconApp.swift` or main view's `onAppear`):

```swift
Task {
    await AIManager.shared.checkServices()

    // Start priority pipeline if OpenRouter is configured
    if AIManager.shared.isOpenRouterConfigured {
        AIManager.shared.startPriorityPipeline()
    }
}
```

## Configuration from Settings

When user updates settings, call:

```swift
// When VIP emails change
await AIManager.shared.setPriorityVIPEmails(newEmails)

// When daily limit changes
AIManager.shared.setPriorityDailyLimit(newLimit)
```

## Manual Trigger

For a "Refresh Priorities" button:

```swift
Button("Analyze Now") {
    Task {
        await AIManager.shared.triggerPriorityAnalysis()
    }
}
```

## Observing State

The pipeline publishes state via `@Published` properties. To observe:

```swift
// In your view
@StateObject private var aiManager = AIManager.shared

var body: some View {
    let stats = aiManager.priorityPipelineStats

    Text("Tokens: \(stats.tokensUsedToday)/\(stats.dailyTokenLimit)")
    if stats.isLimitReached {
        Text("Daily limit reached")
    }
}
```
