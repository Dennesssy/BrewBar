import Foundation

private final class ProcessOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var outputData = Data()
    private var errorData = Data()
    private var timeoutItem: DispatchWorkItem?

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

    func cancelTimeout() {
        lock.lock()
        let item = timeoutItem
        lock.unlock()
        item?.cancel()
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

            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            box.setTimeoutItem(timeoutItem)

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { proc in
                box.cancelTimeout()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let (finalOutput, finalError) = box.snapshot()

                if proc.terminationStatus != 0 {
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
                box.cancelTimeout()
                continuation.resume(throwing: BrewBarError.commandFailed(command: command, error: error.localizedDescription))
            }
        }
    }
}
