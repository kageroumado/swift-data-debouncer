import Foundation
import os
import SwiftData

/// Coalesces rapid SwiftData saves into a single debounced write.
///
/// SwiftData's `ModelContext.save()` is synchronous and can be expensive — it
/// flushes pending inserts, deletes, and updates to disk. When code mutates the
/// graph in rapid bursts (typing into a bound field, scrubbing a slider,
/// importing many objects), naively calling `save()` after each change creates
/// I/O storms that block the main thread.
///
/// `Debouncer` wraps the same `ModelContext` and exposes:
///
/// - ``scheduleSave()`` — cancel any pending save, schedule one after the
///   debounce delay. Multiple rapid calls coalesce into a single write.
/// - ``saveImmediately()`` — cancel pending and save now. Use sparingly
///   (e.g., right before app termination).
/// - ``cancelPendingSave()`` — drop a queued save without writing.
///
/// ## Usage
///
/// ```swift
/// @Observable
/// final class BookmarksManager {
///     private let debouncer: SwiftDataDebouncer.Debouncer
///
///     init(modelContext: ModelContext) {
///         self.debouncer = .init(modelContext: modelContext)
///     }
///
///     func rename(_ bookmark: Bookmark, to title: String) {
///         bookmark.title = title
///         debouncer.scheduleSave()
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// `Debouncer` is `@MainActor`-isolated because `ModelContext` must be accessed
/// from the actor that owns it, and the SwiftData defaults align with the
/// main actor. Mutate your `@Model` objects on the main actor and call
/// ``scheduleSave()`` from there.
@MainActor
public final class Debouncer {
    // MARK: - Properties

    private let modelContext: ModelContext
    private let debounceDelay: TimeInterval
    private let logger: Logger

    private var saveTask: Task<Void, any Error>?

    // MARK: - Initialization

    /// Creates a debouncer for the given context.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData context whose saves should be coalesced.
    ///   - debounceDelay: How long to wait after the last `scheduleSave()` before
    ///     actually saving, in seconds. Defaults to 0.5 — small enough to feel
    ///     instant, large enough to coalesce typical bursts.
    ///   - logger: Logger used for diagnostics when a save fails. Defaults to
    ///     a disabled logger (silent).
    public init(
        modelContext: ModelContext,
        debounceDelay: TimeInterval = 0.5,
        logger: Logger = Logger(.disabled),
    ) {
        self.modelContext = modelContext
        self.debounceDelay = debounceDelay
        self.logger = logger
    }

    deinit {
        saveTask?.cancel()
    }

    // MARK: - Public API

    /// Schedules a debounced save.
    ///
    /// Cancels any pending save and queues a new one after ``debounceDelay``
    /// seconds. Rapid repeated calls collapse into a single write.
    public func scheduleSave() {
        saveTask?.cancel()
        let task = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            try await Task.sleep(for: .seconds(self.debounceDelay))

            try Task.checkCancellation()
            self.performSave()
            self.saveTask = nil
        }
        saveTask = task
    }

    /// Saves immediately, cancelling any pending debounced save.
    ///
    /// Use sparingly — prefer ``scheduleSave()`` for routine writes. Good fits
    /// include app termination, view-disappear hooks where you need durability,
    /// and explicit user-driven "Save" actions.
    public func saveImmediately() {
        cancelPendingSave()
        performSave()
    }

    /// Cancels any pending debounced save without writing.
    ///
    /// Useful when the manager is being torn down or the modification is being
    /// rolled back.
    public func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    /// Whether there is a save currently scheduled and not yet executed.
    public var hasPendingSave: Bool {
        guard let task = saveTask else { return false }
        return !task.isCancelled
    }

    // MARK: - Private

    private func performSave() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            logger.error("SwiftDataDebouncer save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
