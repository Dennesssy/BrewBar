import Foundation

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

    /// Grace period after SIGTERM before escalating to SIGKILL, so a process
    /// that ignores SIGTERM can't hang execute(...) forever.
    private static let killEscalationDelay: TimeInterval = 5

    public init() {}

    public typealias OutputHandler = @Sendable (String) -> Void

    public func execute(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 300,
        outputHandler: OutputHandler? = nil
    ) async throws -> String {
        isRunning = true
        defer { isRunning = false }

        let command = ([executablePath] + arguments).joined(separator: " ")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

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
                }
            }

            let killItem = DispatchWorkItem {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            box.setKillItem(killItem)

            let timeoutItem = DispatchWorkItem {
                box.markTimedOut()
                if process.isRunning {
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
                } else if proc.terminationStatus != 0 {
                    let errMessage = finalError.isEmpty ? finalOutput : finalError
                    continuation.resume(throwing: BrewBarError.commandFailed(
                        command: command,
                        error: errMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } else {
                    continuation.resume(returning: finalOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            do {
                try process.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                box.cancelTimeoutWork()
                continuation.resume(throwing: BrewBarError.commandFailed(command: command, error: error.localizedDescription))
            }
        }
    }
}
