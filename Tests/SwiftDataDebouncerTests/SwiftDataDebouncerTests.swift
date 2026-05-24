import Foundation
import SwiftData
import Testing

@testable import SwiftDataDebouncer

@Model
final class Note {
    var title: String
    var body: String

    init(title: String, body: String = "") {
        self.title = title
        self.body = body
    }
}

@MainActor
@Suite("SwiftDataDebouncer.Debouncer")
struct DebouncerTests {
    // MARK: - Fixture

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Note.self, configurations: config)
        return ModelContext(container)
    }

    // MARK: - Tests

    @Test("scheduleSave coalesces a burst into one write")
    func coalescesBurst() async throws {
        let context = try makeContext()
        let debouncer = Debouncer(modelContext: context, debounceDelay: 0.05)

        let note = Note(title: "First")
        context.insert(note)
        #expect(context.hasChanges)

        // Hammer schedule — each call cancels the prior task.
        for _ in 0..<10 {
            debouncer.scheduleSave()
        }

        // Before the delay elapses, the save shouldn't have happened.
        #expect(context.hasChanges)

        try await Task.sleep(for: .milliseconds(150))

        // After the delay, the single coalesced save has run.
        #expect(!context.hasChanges)
    }

    @Test("scheduleSave does nothing if context has no changes")
    func noOpWithoutChanges() async throws {
        let context = try makeContext()
        let debouncer = Debouncer(modelContext: context, debounceDelay: 0.05)

        debouncer.scheduleSave()
        try await Task.sleep(for: .milliseconds(100))

        // No crash, no work — hasChanges remains false throughout.
        #expect(!context.hasChanges)
    }

    @Test("saveImmediately flushes synchronously and clears the pending task")
    func saveImmediatelyFlushes() async throws {
        let context = try makeContext()
        let debouncer = Debouncer(modelContext: context, debounceDelay: 5) // long delay

        context.insert(Note(title: "Now"))
        debouncer.scheduleSave()
        #expect(debouncer.hasPendingSave)
        #expect(context.hasChanges)

        debouncer.saveImmediately()

        #expect(!context.hasChanges)
        #expect(!debouncer.hasPendingSave)
    }

    @Test("cancelPendingSave drops the queued save without writing")
    func cancelPendingDropsSave() async throws {
        let context = try makeContext()
        let debouncer = Debouncer(modelContext: context, debounceDelay: 0.05)

        context.insert(Note(title: "Pending"))
        debouncer.scheduleSave()
        debouncer.cancelPendingSave()

        try await Task.sleep(for: .milliseconds(100))

        // Save was cancelled, so the context still has unsaved changes.
        #expect(context.hasChanges)
    }

    @Test("subsequent scheduleSave after a flush schedules a fresh save")
    func reschedulesAfterFlush() async throws {
        let context = try makeContext()
        let debouncer = Debouncer(modelContext: context, debounceDelay: 0.05)

        context.insert(Note(title: "A"))
        debouncer.scheduleSave()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!context.hasChanges)

        context.insert(Note(title: "B"))
        debouncer.scheduleSave()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!context.hasChanges)

        // Verify B is actually persisted.
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.title)])
        let notes = try context.fetch(descriptor)
        #expect(notes.map(\.title) == ["A", "B"])
    }

    @Test("hasPendingSave reflects scheduled state")
    func hasPendingReflectsScheduledState() async throws {
        let context = try makeContext()
        let debouncer = Debouncer(modelContext: context, debounceDelay: 0.1)

        #expect(!debouncer.hasPendingSave)

        context.insert(Note(title: "X"))
        debouncer.scheduleSave()
        #expect(debouncer.hasPendingSave)

        try await Task.sleep(for: .milliseconds(150))
        #expect(!debouncer.hasPendingSave)
    }
}
