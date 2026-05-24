# SwiftDataDebouncer

Coalesce rapid SwiftData saves into a single debounced write.

`ModelContext.save()` is synchronous and not cheap — it flushes pending inserts, updates, and deletes through the persistent coordinator to disk. Call it on every keystroke, slider tick, or batch-import row and you'll feel it: dropped frames, beach-balling, an Instruments trace full of SQLite I/O.

This package gives you a `Debouncer` that absorbs the burst and saves once after things settle down.

## What it does

```swift
debouncer.scheduleSave()        // cancel any pending save, queue one in N seconds
debouncer.saveImmediately()     // flush now (use at termination / view dismiss)
debouncer.cancelPendingSave()   // drop the queued save without writing
debouncer.hasPendingSave        // peek at the scheduled state
```

Every actual write checks `modelContext.hasChanges` first, so a save against an empty context does no I/O.

## Installation

Requires macOS 14 / iOS 17 / tvOS 17 / watchOS 10 / visionOS 1.

```swift
dependencies: [
    .package(url: "https://github.com/kageroumado/swift-data-debouncer", from: "1.0.0"),
],
targets: [
    .target(name: "App", dependencies: ["SwiftDataDebouncer"]),
],
```

## Usage

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

Pass an `os.Logger` if you want failed saves logged. Default is `Logger(.disabled)` — completely silent.

```swift
import os

let log = Logger(subsystem: "com.example.app", category: "swiftdata")
let debouncer = Debouncer(modelContext: ctx, logger: log)
```

## Thread safety

`Debouncer` is `@MainActor`-isolated, matching the default isolation of `ModelContext`. Mutate your `@Model` objects on the main actor and call `scheduleSave()` from there. If you have a background `@ModelActor`, instantiate a separate `Debouncer` against that actor's context.

## In production

Used by [Refrax](https://github.com/kageroumado/refrax), a WebKit-based browser for macOS, in five managers that each used to inline the same debounced-save pattern: bookmarks, history, browser state, site settings, and downloads. Consolidating them into this single primitive caught a class of bugs where some sites quietly used different debounce delays, and one used no debounce at all — which is how a 50-tab session-restore could stutter for half a second.

## License

[MIT](LICENSE).
