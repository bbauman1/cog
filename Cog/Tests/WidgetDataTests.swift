import Foundation
import Testing
@testable import Cog

@Suite("Widget session data")
struct WidgetDataTests {

    private func makeEntry(
        sessionId: String = "devin-1",
        title: String = "Fix bug",
        statusRaw: String = "running",
        statusDetailRaw: String? = "working",
        acus: Double = 1.5
    ) -> WidgetSessionEntry {
        WidgetSessionEntry(
            sessionId: sessionId,
            title: title,
            statusRaw: statusRaw,
            statusDetailRaw: statusDetailRaw,
            acusConsumed: acus,
            createdAt: Int(Date().timeIntervalSince1970)
        )
    }

    // MARK: - Status symbols

    @Test("Running/working shows play icon")
    func runningWorkingSymbol() {
        let entry = makeEntry(statusRaw: "running", statusDetailRaw: "working")
        #expect(entry.statusSymbol == "play.circle.fill")
    }

    @Test("Running/waiting_for_user shows question icon")
    func waitingForUserSymbol() {
        let entry = makeEntry(statusRaw: "running", statusDetailRaw: "waiting_for_user")
        #expect(entry.statusSymbol == "person.fill.questionmark")
    }

    @Test("Running/waiting_for_approval shows shield icon")
    func waitingForApprovalSymbol() {
        let entry = makeEntry(statusRaw: "running", statusDetailRaw: "waiting_for_approval")
        #expect(entry.statusSymbol == "checkmark.shield")
    }

    @Test("Suspended shows pause icon")
    func suspendedSymbol() {
        let entry = makeEntry(statusRaw: "suspended")
        #expect(entry.statusSymbol == "pause.circle.fill")
    }

    @Test("Exit/finished shows checkmark icon")
    func finishedSymbol() {
        let entry = makeEntry(statusRaw: "exit", statusDetailRaw: "finished")
        #expect(entry.statusSymbol == "checkmark.circle.fill")
    }

    @Test("Exit/other shows stop icon")
    func exitOtherSymbol() {
        let entry = makeEntry(statusRaw: "exit", statusDetailRaw: "inactivity")
        #expect(entry.statusSymbol == "stop.circle.fill")
    }

    @Test("Error shows warning icon")
    func errorSymbol() {
        let entry = makeEntry(statusRaw: "error")
        #expect(entry.statusSymbol == "exclamationmark.triangle.fill")
    }

    @Test("Unknown status shows dotted circle")
    func unknownSymbol() {
        let entry = makeEntry(statusRaw: "new")
        #expect(entry.statusSymbol == "circle.dotted")
    }

    // MARK: - Status labels

    @Test("Working label")
    func workingLabel() {
        let entry = makeEntry(statusDetailRaw: "working")
        #expect(entry.statusLabel == "Working...")
    }

    @Test("Waiting for user label")
    func waitingLabel() {
        let entry = makeEntry(statusDetailRaw: "waiting_for_user")
        #expect(entry.statusLabel == "Needs input")
    }

    @Test("Waiting for approval label")
    func approvalLabel() {
        let entry = makeEntry(statusDetailRaw: "waiting_for_approval")
        #expect(entry.statusLabel == "Needs approval")
    }

    @Test("Finished label")
    func finishedLabel() {
        let entry = makeEntry(statusDetailRaw: "finished")
        #expect(entry.statusLabel == "Completed")
    }

    @Test("Error label")
    func errorLabel() {
        let entry = makeEntry(statusDetailRaw: "error")
        #expect(entry.statusLabel == "Error")
    }

    @Test("Unknown detail falls back to capitalized status")
    func unknownDetailLabel() {
        let entry = makeEntry(statusRaw: "running", statusDetailRaw: nil)
        #expect(entry.statusLabel == "Running")
    }

    // MARK: - Display title

    @Test("displayTitle returns title")
    func displayTitle() {
        let entry = makeEntry(title: "Deploy feature")
        #expect(entry.displayTitle == "Deploy feature")
    }

    // MARK: - Snapshot encoding round-trip

    @Test("Snapshot encodes and decodes")
    func snapshotRoundTrip() throws {
        let entries = [
            makeEntry(sessionId: "s1", title: "Task A"),
            makeEntry(sessionId: "s2", title: "Task B"),
        ]
        let snapshot = WidgetSessionSnapshot(
            sessions: entries,
            totalActive: 2,
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSessionSnapshot.self, from: data)

        #expect(decoded.sessions.count == 2)
        #expect(decoded.totalActive == 2)
        #expect(decoded.sessions[0].sessionId == "s1")
        #expect(decoded.sessions[1].title == "Task B")
    }
}
