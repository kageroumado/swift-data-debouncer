# swift-data-debouncer

SwiftDataDebouncer combines bursts of edits into one `ModelContext.save()` after a delay. It skips unchanged contexts and lets you flush immediately when a view closes or the app enters the background.

```swift
.package(url: "https://github.com/kageroumado/swift-data-debouncer", from: "1.0.0")
```

## Highlights

- Coalesce a burst of edits into one delayed SwiftData save.
- Flush pending work at dismissal or backgrounding.
- Skip writes when the ModelContext has no changes.

<details>
<summary>Features and API reference</summary>

### What it does

```swift
debouncer.scheduleSave()        // cancel any pending save, queue one in N seconds
debouncer.saveImmediately()     // flush now (use at termination / view dismiss)
debouncer.cancelPendingSave()   // drop the queued save without writing
debouncer.hasPendingSave        // peek at the scheduled state
```

Every actual write checks `modelContext.hasChanges` first, so a save against an empty context does no I/O.

### Usage

```swift
import SwiftData
import SwiftDataDebouncer

@Observable
final class BookmarksManager {
    private let debouncer: Debouncer

    init(modelContext: ModelContext) {
        self.debouncer = Debouncer(modelContext: modelContext, debounceDelay: 0.5)
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        bookmark.title = title
        debouncer.scheduleSave()   // keystrokes coalesce into one write
    }
}
```

Flush when going to the background:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .background {
        debouncer.saveImmediately()
    }
}
```

### Logging

Pass an `os.Logger` to record failed saves. The default is `Logger(.disabled)`.

```swift
import os

let log = Logger(subsystem: "com.example.app", category: "swiftdata")
let debouncer = Debouncer(modelContext: ctx, logger: log)
```

### Thread safety

`Debouncer` is `@MainActor`-isolated, matching the default isolation of `ModelContext`. Mutate your `@Model` objects on the main actor and call `scheduleSave()` from there. If you have a background `@ModelActor`, instantiate a separate `Debouncer` against that actor's context.

</details>

## Notes

- Swift Package Manager product: `SwiftDataDebouncer`.
- macOS 14 / iOS 17 / tvOS 17 / watchOS 10 / visionOS 1.
