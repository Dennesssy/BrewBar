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

/// Incremental UTF-8 decoder for pipe chunks. A multibyte character can be
/// split across `readabilityHandler` callbacks; `String(data:encoding:)`
/// returns nil for a partial sequence, which silently dropped those bytes
/// from streamed console output. Buffers the incomplete tail until the rest
/// arrives.
private final class UTF8ChunkDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    /// Appends `data` and returns the decodable string, holding back any
    /// trailing bytes that form an incomplete UTF-8 sequence.
    func decode(_ data: Data) -> String? {
        lock.lock()
        pending.append(data)
        let safeLength = Self.utf8SafePrefixLength(pending)
        guard safeLength > 0 else {
            // Nothing decodable yet — but don't buffer forever if the stream
            // is genuinely not UTF-8.
            if pending.count > 64 {
                let lossy = String(decoding: pending, as: UTF8.self)
                pending.removeAll(keepingCapacity: true)
                lock.unlock()
                return lossy
            }
            lock.unlock()
            return nil
        }
        let chunk = pending.prefix(safeLength)
        pending.removeFirst(safeLength)
        lock.unlock()
        return String(decoding: chunk, as: UTF8.self)
    }

    /// Length of the longest prefix that ends on a UTF-8 sequence boundary.
    /// An incomplete trailing sequence (lead byte expecting more continuation
    /// bytes than remain) is excluded.
    private static func utf8SafePrefixLength(_ data: Data) -> Int {
        var i = data.startIndex
        var lastBoundary = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            let length: Int
            if byte < 0x80 {
                length = 1
            } else if byte & 0xE0 == 0xC0 {
                length = 2
            } else if byte & 0xF0 == 0xE0 {
                length = 3
            } else if byte & 0xF8 == 0xF0 {
                length = 4
            } else {
                // Invalid lead byte: step over it so it decodes as U+FFFD
                // instead of stalling the buffer.
                lastBoundary = data.index(after: i)
                i = lastBoundary
                continue
            }
            // nil means the sequence runs past the buffer end — an incomplete
            // tail split across chunks; hold it for the next decode.
            guard let end = data.index(i, offsetBy: length, limitedBy: data.endIndex) else { break }
            lastBoundary = end
            i = end
        }
        return data.distance(from: data.startIndex, to: lastBoundary)
    }
}

public actor ProcessManager {
    /// Every process this manager has launched and not yet seen terminate.
    /// execute() is reentrant, so several can be in flight at once.
    private var inFlight: [ObjectIdentifier: Process] = [:]

    /// Grace period after SIGTERM before escalating to SIGKILL, so a process
    /// that ignores SIGTERM can't hang execute(...) forever.
    private static let killEscalationDelay: TimeInterval = 5

    public init() {}

    public var isRunning: Bool { !inFlight.isEmpty }

    public func cancel() {
        for process in inFlight.values where process.isRunning {
            // Try SIGTERM first
            process.terminate()
            // Schedule SIGKILL if it doesn't die
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.killEscalationDelay) {
                if process.isRunning {
                    kill(-process.processIdentifier, SIGKILL)
                }
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
        let command = ([executablePath] + arguments).joined(separator: " ")

        return try await withCheckedThrowingContinuation { continuation in
            // This body runs synchronously on the actor, so registering here
            // is ordered before any cancel() and before the process can exit.
            let process = Process()
            let key = ObjectIdentifier(process)
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
            // A child inheriting our stdin could block on a prompt or, under
            // brewbar-mcp, swallow the JSON-RPC request stream.
            process.standardInput = FileHandle.nullDevice

            let box = ProcessOutputBox()
            let outputDecoder = UTF8ChunkDecoder()
            let errorDecoder = UTF8ChunkDecoder()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    box.appendOutput(data)
                    if let handler = outputHandler, let str = outputDecoder.decode(data) {
                        handler(str)
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    box.appendError(data)
                    if let handler = outputHandler, let str = errorDecoder.decode(data) {
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

                // Best-effort drain of everything the kernel has buffered.
                // `availableData` is non-blocking — it returns empty at EOF
                // or when a background grandchild still holds the write end
                // without producing data — so looping it can't hang the way
                // readDataToEndOfFile() would. Nil-ing the readability
                // handlers first drops callbacks still queued on their
                // private queues; draining here is what recovers that tail.
                let remainingOutput = ProcessManager.drainAvailableData(from: outputPipe.fileHandleForReading)
                if !remainingOutput.isEmpty {
                    box.appendOutput(remainingOutput)
                }
                let remainingError = ProcessManager.drainAvailableData(from: errorPipe.fileHandleForReading)
                if !remainingError.isEmpty {
                    box.appendError(remainingError)
                }

                // Stream the drained tail (plus any decoder-held bytes) to the
                // live console before reporting the result.
                if let handler = outputHandler {
                    if let str = outputDecoder.decode(remainingOutput), !str.isEmpty { handler(str) }
                    if let str = errorDecoder.decode(remainingError), !str.isEmpty { handler(str) }
                    if let str = outputDecoder.decode(Data()), !str.isEmpty { handler(str) }
                    if let str = errorDecoder.decode(Data()), !str.isEmpty { handler(str) }
                }

                let (finalOutput, finalError) = box.snapshot()

                let outcome: Result<String, any Error>
                if box.hasTimedOut() {
                    outcome = .failure(BrewBarError.commandTimeout(command))
                } else if proc.terminationStatus != 0 && !allowNonZeroExit {
                    let errMessage = finalError.isEmpty ? finalOutput : finalError
                    outcome = .failure(BrewBarError.commandFailed(
                        command: command,
                        error: errMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } else {
                    let returnOutput = finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let returnError = finalError.trimmingCharacters(in: .whitespacesAndNewlines)
                    outcome = .success(returnOutput.isEmpty ? returnError : returnOutput)
                }

                // Unregister before resuming so isRunning is already false
                // by the time the caller's execute() returns.
                Task {
                    await self.unregister(key)
                    continuation.resume(with: outcome)
                }
            }

            inFlight[key] = process

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
                inFlight[key] = nil
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                box.cancelTimeoutWork()
                continuation.resume(throwing: BrewBarError.commandFailed(command: command, error: error.localizedDescription))
            }
        }
    }

    /// Reads every byte currently buffered on a pipe without blocking.
    /// `availableData` returns an empty `Data` at EOF and when no data is
    /// ready, so the loop terminates as soon as the kernel buffer is empty —
    /// even if a backgrounded grandchild still holds the write end open.
    private static func drainAvailableData(from handle: FileHandle) -> Data {
        var all = Data()
        // Cap iterations defensively; each pass can return up to the pipe
        // buffer size, so this still covers multi-MB tails.
        for _ in 0..<10_000 {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            all.append(chunk)
        }
        return all
    }

    private func unregister(_ key: ObjectIdentifier) {
        inFlight[key] = nil
    }
}
