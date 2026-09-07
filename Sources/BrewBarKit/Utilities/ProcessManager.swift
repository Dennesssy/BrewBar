import Foundation

public actor ProcessManager {
    public private(set) var isRunning: Bool = false

    public init() {}

    public typealias OutputHandler = @Sendable (String) -> Void

    public func execute(
        command: String,
        timeout: TimeInterval = 300,
        outputHandler: OutputHandler? = nil
    ) async throws -> String {
        isRunning = true
        defer { isRunning = false }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var outputData = Data()
            var errorData = Data()
            var didTimeout = false

            let lock = NSLock()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    lock.lock()
                    outputData.append(data)
                    lock.unlock()
                    if let handler = outputHandler, let str = String(data: data, encoding: .utf8) {
                        handler(str)
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    lock.lock()
                    errorData.append(data)
                    lock.unlock()
                }
            }

            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    lock.lock()
                    didTimeout = true
                    lock.unlock()
                    process.terminate()
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { proc in
                timeoutItem.cancel()

                // Step 1: Stop readability callbacks to prevent further appends
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // Step 2: Drain remaining data from pipes to EOF
                // This ensures we capture any data still in the pipe buffers
                let remainingOutput = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
                let remainingError = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()

                // Step 3: Append remaining data and construct final strings under lock
                lock.lock()
                if !remainingOutput.isEmpty {
                    outputData.append(remainingOutput)
                    // Stream remaining output to handler if provided
                    if let handler = outputHandler, let str = String(data: remainingOutput, encoding: .utf8) {
                        lock.unlock()
                        handler(str)
                        lock.lock()
                    }
                }
                if !remainingError.isEmpty {
                    errorData.append(remainingError)
                }

                let finalOutput = String(data: outputData, encoding: .utf8) ?? ""
                let finalError = String(data: errorData, encoding: .utf8) ?? ""
                let wasTimeout = didTimeout
                lock.unlock()

                // Step 4: Resume continuation with final result or error
                if wasTimeout {
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
                timeoutItem.cancel()
                continuation.resume(throwing: BrewBarError.commandFailed(command: command, error: error.localizedDescription))
            }
        }
    }
}
