import AVFoundation
import Foundation

enum RecorderError: LocalizedError {
    case permissionDenied
    case engineStartFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone permission denied"
        case .engineStartFailed(let msg): return "Audio engine failed: \(msg)"
        case .writeFailed(let msg): return "Audio file write failed: \(msg)"
        }
    }
}

actor AudioRecorder {
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var writeErrorMessage: String?
    private var previousDefaultInputUID: String?

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
        writeErrorMessage = nil

        let resourceValues = try? tempDir.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        if let available = resourceValues?.volumeAvailableCapacity, available < 100 * 1024 * 1024 {
            throw RecorderError.engineStartFailed("Insufficient disk space. At least 100 MB is recommended.")
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let format = inputNode.outputFormat(forBus: 0)
        let outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        self.outputFile = outputFile

        let selectedUID = SettingsManager.shared.selectedInputDeviceUID
        if !selectedUID.isEmpty {
            previousDefaultInputUID = AudioDeviceManager.currentDefaultInputDeviceUID()
            if previousDefaultInputUID != selectedUID {
                AudioDeviceManager.setDefaultInputDevice(uid: selectedUID)
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            do {
                try outputFile.write(from: buffer)
            } catch {
                Task {
                    await self.recordWriteFailure(error.localizedDescription)
                }
            }
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

    func stopRecording() throws {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil

        if let previousUID = previousDefaultInputUID {
            AudioDeviceManager.setDefaultInputDevice(uid: previousUID)
            previousDefaultInputUID = nil
        }

        if let writeErrorMessage {
            self.writeErrorMessage = nil
            throw RecorderError.writeFailed(writeErrorMessage)
        }
    }

    func getOutputURL() -> URL? {
        outputURL
    }

    private func recordWriteFailure(_ message: String) async {
        if writeErrorMessage == nil {
            writeErrorMessage = message
        }
    }
}
