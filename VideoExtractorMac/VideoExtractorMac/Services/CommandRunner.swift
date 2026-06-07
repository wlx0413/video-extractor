import Darwin
import Foundation

struct CommandOutput {
    enum Stream {
        case stdout
        case stderr
    }

    var stream: Stream
    var text: String
}

struct CommandResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var succeeded: Bool {
        exitCode == 0
    }
}

private final class CommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""

    func append(_ text: String, stream: CommandOutput.Stream) {
        lock.lock()
        switch stream {
        case .stdout:
            stdout += text
        case .stderr:
            stderr += text
        }
        lock.unlock()
    }

    func result(exitCode: Int32) -> CommandResult {
        lock.lock()
        let result = CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
        lock.unlock()
        return result
    }
}

final class CommandRunner {
    static let shared = CommandRunner()

    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]

    func run(
        id: UUID = UUID(),
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        outputHandler: @escaping (CommandOutput) -> Void = { _ in }
    ) async throws -> CommandResult {
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw AppError.toolUnavailable(executableURL.lastPathComponent)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let buffer = CommandOutputBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false, let text = String(data: data, encoding: .utf8) else {
                return
            }
            buffer.append(text, stream: .stdout)
            outputHandler(CommandOutput(stream: .stdout, text: text))
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false, let text = String(data: data, encoding: .utf8) else {
                return
            }
            buffer.append(text, stream: .stderr)
            outputHandler(CommandOutput(stream: .stderr, text: text))
        }

        Task {
            await AppLogger.shared.command(executableURL, arguments: arguments)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak self] terminatedProcess in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    let result = buffer.result(exitCode: terminatedProcess.terminationStatus)

                    self?.unregister(id: id)
                    if result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Task {
                            await AppLogger.shared.commandError(result.stderr)
                        }
                    }
                    continuation.resume(returning: result)
                }

                do {
                    register(process, id: id)
                    try process.run()
                } catch {
                    unregister(id: id)
                    continuation.resume(throwing: AppError.toolUnavailable(executableURL.lastPathComponent))
                }
            }
        } onCancel: { [weak self] in
            self?.cancel(id: id)
        }
    }

    func cancel(id: UUID) {
        lock.lock()
        let process = processes[id]
        lock.unlock()

        if process?.isRunning == true {
            _ = sendSignal(SIGCONT, to: process)
            process?.terminate()
        }
    }

    @discardableResult
    func pause(id: UUID) -> Bool {
        lock.lock()
        let process = processes[id]
        lock.unlock()

        return sendSignal(SIGSTOP, to: process)
    }

    @discardableResult
    func resume(id: UUID) -> Bool {
        lock.lock()
        let process = processes[id]
        lock.unlock()

        return sendSignal(SIGCONT, to: process)
    }

    private func register(_ process: Process, id: UUID) {
        lock.lock()
        processes[id] = process
        lock.unlock()
    }

    private func unregister(id: UUID) {
        lock.lock()
        processes[id] = nil
        lock.unlock()
    }

    private func sendSignal(_ signal: Int32, to process: Process?) -> Bool {
        guard let process, process.isRunning else {
            return false
        }

        let pid = process.processIdentifier
        guard pid > 0 else {
            return false
        }

        return Darwin.kill(pid, signal) == 0
    }
}
