import Cocoa
import Foundation

enum RecordingSessionError: LocalizedError {
    case recordingInProgress
    case notRecording
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .recordingInProgress: return "Recording already in progress"
        case .notRecording: return "Not currently recording"
        case .emptyTranscript: return "Transcript is empty"
        }
    }
}

@MainActor
protocol RecordingSessionDelegate: AnyObject {
    func recordingSession(_ session: RecordingSession, didUpdate status: WorkflowStatus)
    func recordingSession(_ session: RecordingSession, didReceive response: TranscriptionResponse)
    func recordingSession(_ session: RecordingSession, didFailWith error: Error)
}

actor RecordingSession {
    private let recorder = AudioRecorder()
    private let paster = PasteEngine()
    private var isRecording = false
    private var isProcessing = false

    weak var delegate: RecordingSessionDelegate?

    func setDelegate(_ delegate: RecordingSessionDelegate?) {
        self.delegate = delegate
    }

    var currentStatus: WorkflowStatus = .idle

    func toggleRecording(pasteTargetBundleID: String?) async {
        if isRecording {
            await stop(pasteTargetBundleID: pasteTargetBundleID)
        } else {
            await start()
        }
    }

    func start() async {
        guard !isRecording else { return }
        do {
            _ = try await recorder.startRecording()
            isRecording = true
            await updateStatus(.recording)
        } catch {
            await updateStatus(.error)
            await delegate?.recordingSession(self, didFailWith: error)
        }
    }

    func stop(pasteTargetBundleID: String?) async {
        guard isRecording else { return }

        let recordedURL = await recorder.getOutputURL()
        defer {
            if let url = recordedURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        do {
            try await recorder.stopRecording()
        } catch {
            isRecording = false
            await updateStatus(.error)
            await delegate?.recordingSession(self, didFailWith: error)
            return
        }
        isRecording = false
        await updateStatus(.transcribing)

        guard let captureURL = recordedURL else {
            await updateStatus(.idle)
            return
        }

        do {
            let result = try await ServerClient().transcribe(fileURL: captureURL)
            await delegate?.recordingSession(self, didReceive: result)

            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await updateStatus(.idle)
                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
            await reactivatePasteTarget(bundleIdentifier: pasteTargetBundleID)
            try? await Task.sleep(nanoseconds: 150_000_000)

            do {
                await updateStatus(.pasting)
                try await paster.pasteText(result.text)
                await updateStatus(.pasted)
            } catch PasteError.accessibilityDenied {
                await paster.copyToClipboard(result.text)
                await updateStatus(.copiedToClipboard)
                await delegate?.recordingSession(self, didFailWith: PasteError.accessibilityDenied)
            } catch {
                await paster.copyToClipboard(result.text)
                await updateStatus(.copiedToClipboard)
            }
        } catch {
            await updateStatus(.error)
            await delegate?.recordingSession(self, didFailWith: error)
        }
    }

    func pasteLastTranscript(_ transcript: String) async {
        guard !transcript.isEmpty else { return }
        do {
            try await paster.pasteText(transcript)
            await updateStatus(.pasted)
        } catch PasteError.accessibilityDenied {
            await paster.copyToClipboard(transcript)
            await updateStatus(.copiedToClipboard)
            await delegate?.recordingSession(self, didFailWith: PasteError.accessibilityDenied)
        } catch {
            await paster.copyToClipboard(transcript)
            await updateStatus(.copiedToClipboard)
        }
    }

    private func updateStatus(_ status: WorkflowStatus) async {
        currentStatus = status
        await delegate?.recordingSession(self, didUpdate: status)
    }

    private func reactivatePasteTarget(bundleIdentifier: String?) async {
        guard let bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier })
        else { return }
        app.activate(options: [])
    }
}
