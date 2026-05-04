import AVFoundation
import Foundation

enum RecorderError: LocalizedError {
    case permissionDenied
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone permission denied"
        case .engineStartFailed(let msg): return "Audio engine failed: \(msg)"
        }
    }
}

actor AudioRecorder {
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?

    var isRecording: Bool {
        engine?.isRunning ?? false
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() async throws -> URL {
        guard await requestPermission() else {
            throw RecorderError.permissionDenied
        }

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("phonos_recording_\(UUID().uuidString).wav")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let format = inputNode.outputFormat(forBus: 0)
        let outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        self.outputFile = outputFile

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? outputFile.write(from: buffer)
        }

        engine.prepare()

        do {
            try engine.start()
        } catch {
            throw RecorderError.engineStartFailed(error.localizedDescription)
        }

        self.engine = engine
        self.outputURL = url
        return url
    }

    func stopRecording() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil
    }

    func getOutputURL() -> URL? {
        outputURL
    }
}
