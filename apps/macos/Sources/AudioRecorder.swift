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
        let url = tempDir.appendingPathComponent("phonos_recording.wav")

        let inputNode = AVAudioEngine().inputNode
        let engine = AVAudioEngine()

        let format = inputNode.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        outputFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            Task { [weak self] in
                guard let self = self, let file = await self.outputFile else { return }
                try? file.write(from: buffer)
            }
        }

        engine.attach(inputNode)
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
