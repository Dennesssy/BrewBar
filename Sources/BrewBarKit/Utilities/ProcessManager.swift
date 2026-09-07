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
                    process.terminate()
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { proc in
                timeoutItem.cancel()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                lock.lock()
                let finalOutput = String(data: outputData, encoding: .utf8) ?? ""
                let finalError = String(data: errorData, encoding: .utf8) ?? ""
                lock.unlock()

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
                timeoutItem.cancel()
                continuation.resume(throwing: BrewBarError.commandFailed(command: command, error: error.localizedDescription))
            }
        }
    }
}
