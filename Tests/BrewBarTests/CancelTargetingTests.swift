// Copyright © 2026 Dennis Stewart. All rights reserved.

import XCTest
@testable import BrewBarKit

/// Cancel must only reach the process owned by the manager it is called on.
/// BrewService keeps user tasks on their own ProcessManager so a background
/// refresh that starts mid-install is never the process Cancel kills.
final class CancelTargetingTests: XCTestCase {

    private actor Flag {
        private(set) var isSet = false
        func set() { isSet = true }
    }

    func testCancelOnTaskManagerLeavesOtherManagerRunning() async throws {
        let taskManager = ProcessManager()
        let refreshManager = ProcessManager()
        let taskDone = Flag()
        let refreshDone = Flag()

        let taskRun = Task<Error?, Never> {
            var failure: Error?
            do {
                _ = try await taskManager.execute(executablePath: "/bin/sleep", arguments: ["30"])
            } catch {
                failure = error
            }
            await taskDone.set()
            return failure
        }
        let refreshRun = Task<Error?, Never> {
            var failure: Error?
            do {
                _ = try await refreshManager.execute(executablePath: "/bin/sleep", arguments: ["30"])
            } catch {
                failure = error
            }
            await refreshDone.set()
            return failure
        }

        // Let both sleeps spawn and register as their manager's current process.
        try await Task.sleep(for: .seconds(1))

        await taskManager.cancel()

        let taskFinished = await waitUntil(seconds: 8) { await taskDone.isSet }
        XCTAssertTrue(taskFinished, "cancelled task process did not finish within 8s")
        // The sleep was killed by SIGTERM, so the task must surface a failure, not success.
        if taskFinished {
            let failure = await taskRun.value
            XCTAssertNotNil(failure)
            if let brewError = failure as? BrewBarError, case .commandFailed = brewError {
                // expected
            } else {
                XCTFail("expected commandFailed after cancel, got \(String(describing: failure))")
            }
        }

        // The other manager's process must be untouched by that cancel.
        let refreshFinishedEarly = await refreshDone.isSet
        XCTAssertFalse(refreshFinishedEarly, "cancel on the task manager killed the refresh process")

        // Clean up the still-running refresh process.
        await refreshManager.cancel()
        let refreshFinished = await waitUntil(seconds: 8) { await refreshDone.isSet }
        XCTAssertTrue(refreshFinished, "refresh process did not exit after its own cancel")
        if refreshFinished {
            _ = await refreshRun.value
        }
    }

    /// Polls `condition` until it returns true or `seconds` elapse.
    private func waitUntil(seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }
}
