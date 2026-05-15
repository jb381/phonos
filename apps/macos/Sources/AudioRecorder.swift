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
    let audioDeviceClient: AudioDeviceClient
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var writeErrorMessage: String?
    private var previousDefaultInputUID: String?

    init(audioDeviceClient: AudioDeviceClient = .live) {
        self.audioDeviceClient = audioDeviceClient
    }

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
        outputURL = nil
        previousDefaultInputUID = nil

        let resourceValues = try? tempDir.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        if let available = resourceValues?.volumeAvailableCapacity, available < 100 * 1024 * 1024 {
            throw RecorderError.engineStartFailed("Insufficient disk space. At least 100 MB is recommended.")
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        var didInstallTap = false
        var startupSucceeded = false

        defer {
            if !startupSucceeded {
                rollbackStartup(didInstallTap: didInstallTap, engine: engine, fileURL: url)
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        let outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        self.outputFile = outputFile

        let selectedUID = SettingsManager.shared.selectedInputDeviceUID
        if !selectedUID.isEmpty {
            previousDefaultInputUID = audioDeviceClient.currentDefaultInputDeviceUID()
            if previousDefaultInputUID != selectedUID {
                _ = audioDeviceClient.setDefaultInputDevice(selectedUID)
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            do {
                try outputFile.write(from: buffer)
            } catch {
                Task {
                    await self.recordWriteFailure(error.localizedDescription)
                }
            }
        }
        didInstallTap = true

        engine.prepare()

        do {
            try engine.start()
        } catch {
            throw RecorderError.engineStartFailed(error.localizedDescription)
        }

        self.engine = engine
        self.outputURL = url
        startupSucceeded = true
        return url
    }

    func stopRecording() throws {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil

        if let previousUID = previousDefaultInputUID {
            _ = audioDeviceClient.setDefaultInputDevice(previousUID)
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

    func rollbackStartup(didInstallTap: Bool, engine: AVAudioEngine, fileURL: URL) {
        if didInstallTap {
            engine.inputNode.removeTap(onBus: 0)
        }
        engine.stop()
        self.engine = nil
        self.outputFile = nil
        self.outputURL = nil

        if let previousUID = previousDefaultInputUID {
            _ = audioDeviceClient.setDefaultInputDevice(previousUID)
            previousDefaultInputUID = nil
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    func setPreviousDefaultInputUIDForTest(_ uid: String?) {
        previousDefaultInputUID = uid
    }

    func getPreviousDefaultInputUIDForTest() -> String? {
        previousDefaultInputUID
    }

    private func recordWriteFailure(_ message: String) async {
        if writeErrorMessage == nil {
            writeErrorMessage = message
        }
    }
}
