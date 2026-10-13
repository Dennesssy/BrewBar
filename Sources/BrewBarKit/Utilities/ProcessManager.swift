// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

private final class ProcessOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var outputData = Data()
    private var errorData = Data()
    private var timeoutItem: DispatchWorkItem?
    private var killItem: DispatchWorkItem?
    private var didTimeOut = false

    func appendOutput(_ data: Data) {
        lock.lock()
        outputData.append(data)
        lock.unlock()
    }

    func appendError(_ data: Data) {
        lock.lock()
        errorData.append(data)
        lock.unlock()
    }

    func setTimeoutItem(_ item: DispatchWorkItem) {
        lock.lock()
        timeoutItem = item
        lock.unlock()
    }

    func setKillItem(_ item: DispatchWorkItem) {
        lock.lock()
        killItem = item
        lock.unlock()
    }

    func markTimedOut() {
        lock.lock()
        didTimeOut = true
        lock.unlock()
    }

    func hasTimedOut() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeOut
    }

    /// Cancels both the SIGTERM timeout and the SIGKILL escalation.
    func cancelTimeoutWork() {
        lock.lock()
        let timeout = timeoutItem
        let kill = killItem
        lock.unlock()
        timeout?.cancel()
        kill?.cancel()
    }

    func snapshot() -> (output: String, error: String) {
        lock.lock()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        lock.unlock()
        return (output, error)
    }
}

public actor ProcessManager {
    public private(set) var isRunning: Bool = false
    private var currentProcess: Process?

    /// Grace period after SIGTERM before escalating to SIGKILL, so a process
    /// that ignores SIGTERM can't hang execute(...) forever.
    private static let killEscalationDelay: TimeInterval = 5

    public init() {}

    public func cancel() {
        guard let process = currentProcess, process.isRunning else { return }
        // Try SIGTERM first
        process.terminate()
        // Schedule SIGKILL if it doesn't die
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.killEscalationDelay) {
            if process.isRunning {
                kill(-process.processIdentifier, SIGKILL)
            }
        }
    }

    public typealias OutputHandler = @Sendable (String) -> Void

    private static func writeAskpassHelper() -> String? {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("BrewBar-askpass", isDirectory: true)
        let path = directory.appendingPathComponent("askpass.sh").path
        let script = """
        #!/bin/bash
        osascript -e 'tell application "SystemUIServer" to activate' -e 'tell application "SystemUIServer" to text returned of (display dialog "Homebrew requires your administrator password to continue." default answer "" with hidden answer with title "BrewBar Authentication")'
        """
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
            // Created with 0700 up front, so there is no window where the script is more permissive.
            guard fileManager.createFile(
                atPath: path,
                contents: Data(script.utf8),
                attributes: [.posixPermissions: 0o700]
            ) else { return nil }
            return path
        } catch {
            return nil
        }
    }

    public func execute(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 300,
        allowNonZeroExit: Bool = false,
        extraEnvironment: [String: String]? = nil,
        outputHandler: OutputHandler? = nil
    ) async throws -> String {
        isRunning = true
        defer { isRunning = false }

        let command = ([executablePath] + arguments).joined(separator: " ")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["HOMEBREW_NO_INTERACTIVE"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            
            // Generate an Apple-approved native authentication dialog for sudo prompts
            // The helper lives in a private (0700) per-user directory and is rewritten on every
            // run, so a stale or tampered copy is never executed with the user's sudo prompt.
            if let askpassPath = ProcessManager.writeAskpassHelper() {
                env["SUDO_ASKPASS"] = askpassPath
            }
            
            if let extraEnv = extraEnvironment {
                for (key, value) in extraEnv {
                    env[key] = value
                }
            }
            
            process.environment = env

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let box = ProcessOutputBox()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    box.appendOutput(data)
                    if let handler = outputHandler, let str = String(data: data, encoding: .utf8) {
                        handler(str)
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    box.appendError(data)
                    if let handler = outputHandler, let str = String(data: data, encoding: .utf8) {
                        handler(str)
                    }
                }
            }

            let killItem = DispatchWorkItem {
                if process.isRunning {
                    // Negative pid targets the whole process group, not just
                    // the direct child — a command that backgrounds work
                    // (e.g. a build script spawning a helper) would otherwise
                    // survive SIGKILL to the leader alone and keep running,
                    // potentially still holding the pipes open.
                    kill(-process.processIdentifier, SIGKILL)
                }
            }
            box.setKillItem(killItem)

            let timeoutItem = DispatchWorkItem {
                // Only flag as timed out if the process is still running at
                // the deadline — otherwise a command that finished (success
                // or failure) right as the timer fires gets misreported as
                // .commandTimeout instead of its real outcome.
                if process.isRunning {
                    box.markTimedOut()
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.killEscalationDelay, execute: killItem)
                }
            }
            box.setTimeoutItem(timeoutItem)

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { proc in
                box.cancelTimeoutWork()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // Best-effort, non-blocking grab of any already-buffered final
                // chunk. Deliberately NOT readDataToEndOfFile(): if a background
                // grandchild inherited the pipe's write end (e.g. `sleep 300 &`),
                // that call blocks until every holder closes it, hanging this
                // handler indefinitely even though our process already exited.
                let remainingOutput = outputPipe.fileHandleForReading.availableData
                if !remainingOutput.isEmpty {
                    box.appendOutput(remainingOutput)
                }
                let remainingError = errorPipe.fileHandleForReading.availableData
                if !remainingError.isEmpty {
                    box.appendError(remainingError)
                }

                let (finalOutput, finalError) = box.snapshot()

                if box.hasTimedOut() {
                    continuation.resume(throwing: BrewBarError.commandTimeout(command))
                } else if proc.terminationStatus != 0 && !allowNonZeroExit {
                    let errMessage = finalError.isEmpty ? finalOutput : finalError
                    continuation.resume(throwing: BrewBarError.commandFailed(
                        command: command,
                        error: errMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } else {
                    let returnOutput = finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let returnError = finalError.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: returnOutput.isEmpty ? returnError : returnOutput)
                }
            }

            Task {
                await self.setCurrentProcess(process)
            }

            do {
                try process.run()
                // Move the child into its own process group so a SIGKILL
                // targeted at -pid reaches only this command's subtree, not
                // our own process group. Best-effort: there's an inherent
                // small race where a grandchild forked in the instant
                // between exec and this call could still land in the old
                // group, but this covers the common "backgrounds a helper"
                // case the timeout escalation is meant to catch.
                setpgid(process.processIdentifier, process.processIdentifier)
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                box.cancelTimeoutWork()
                continuation.resume(throwing: BrewBarError.commandFailed(command: command, error: error.localizedDescription))
            }
        }
    }

    private func setCurrentProcess(_ process: Process) {
        self.currentProcess = process
    }
}
