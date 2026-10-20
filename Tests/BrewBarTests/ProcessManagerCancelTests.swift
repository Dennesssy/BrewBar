// Copyright © 2026 Dennis Stewart. All rights reserved.

import XCTest
@testable import BrewBarKit

/// cancel() must reach every in-flight process on a manager, including ones
/// started by overlapping execute() calls, and must work immediately after
/// execute() has started. Real processes only; nothing here runs brew.
final class ProcessManagerCancelTests: XCTestCase {

    /// Upper bound on how long a cancelled process may take to finish. SIGTERM
    /// ends /bin/sleep at once, so this only fails when cancel() missed a process
    /// and the test waited out the full 30 s sleep.
    private let finishBudget: Duration = .seconds(8)

    /// Spawns `/bin/sh -c 'touch <marker>; exec /bin/sleep 30'`. The marker is
    /// written only after the process is running, so its presence proves the
    /// child has launched. `exec` makes sleep the direct child, so SIGTERM ends it.
    private func sleepingCommand(marker: URL) -> (path: String, args: [String]) {
        ("/bin/sh", ["-c", "touch \"$0\"; exec /bin/sleep 30", marker.path])
    }

    private func waitForMarker(_ marker: URL) async throws {
        for _ in 0..<1000 where !FileManager.default.fileExists(atPath: marker.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "child never started")
    }

    private func waitUntilRunning(_ manager: ProcessManager) async throws {
        var running = await manager.isRunning
        for _ in 0..<1000 where !running {
            try await Task.sleep(for: .milliseconds(10))
            running = await manager.isRunning
        }
        XCTAssertTrue(running, "execute never registered a process")
    }

    func testCancelReachesEveryOverlappingProcess() async throws {
        let manager = ProcessManager()
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrewBarCancelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: markerDir) }

        let markerA = markerDir.appendingPathComponent("a")
        let markerB = markerDir.appendingPathComponent("b")
        let commandA = sleepingCommand(marker: markerA)
        let commandB = sleepingCommand(marker: markerB)

        let first = Task { try await manager.execute(executablePath: commandA.path, arguments: commandA.args) }
        let second = Task { try await manager.execute(executablePath: commandB.path, arguments: commandB.args) }
        try await waitForMarker(markerA)
        try await waitForMarker(markerB)

        let clock = ContinuousClock()
        let start = clock.now
        await manager.cancel()
        _ = await first.result
        _ = await second.result
        let elapsed = start.duration(to: clock.now)

        XCTAssertLessThan(elapsed, finishBudget, "a cancelled process kept running")
    }

    func testCancelImmediatelyAfterExecuteStartsStopsProcess() async throws {
        let manager = ProcessManager()
        let sleeper = Task { try await manager.execute(executablePath: "/bin/sleep", arguments: ["30"]) }
        // Cancel as soon as execute has registered its process; no extra delay.
        try await waitUntilRunning(manager)

        let clock = ContinuousClock()
        let start = clock.now
        await manager.cancel()
        _ = await sleeper.result
        let elapsed = start.duration(to: clock.now)

        XCTAssertLessThan(elapsed, finishBudget, "cancel right after execute started was a no-op")
    }

    func testIsRunningTracksAllInFlightProcesses() async throws {
        let manager = ProcessManager()
        let idle = await manager.isRunning
        XCTAssertFalse(idle)

        let short = Task { try await manager.execute(executablePath: "/bin/sleep", arguments: ["1"]) }
        let long = Task { try await manager.execute(executablePath: "/bin/sleep", arguments: ["3"]) }
        try await waitUntilRunning(manager)

        _ = try await short.value
        let stillRunning = await manager.isRunning
        XCTAssertTrue(stillRunning, "isRunning cleared while a second process was still running")

        _ = try await long.value
        let afterBoth = await manager.isRunning
        XCTAssertFalse(afterBoth, "isRunning stayed true after every process ended")
    }
}
