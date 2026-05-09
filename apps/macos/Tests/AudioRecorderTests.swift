import AVFoundation
import XCTest

@testable import Phonos

final class AudioRecorderTests: XCTestCase {
    private final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private func makeTempFile() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_rollback_\(UUID().uuidString).wav")
        try? Data("test-audio".utf8).write(to: url)
        return url
    }

    // MARK: - rollbackStartup tests

    func testRollbackStartupRestoresPreviousInputDevice() async {
        let setDefaultInputDeviceCalls = CallLog()
        let client = AudioDeviceClient(
            availableInputDevices: { [] },
            setDefaultInputDevice: { uid in
                setDefaultInputDeviceCalls.append(uid)
                return true
            },
            currentDefaultInputDeviceUID: { nil }
        )
        let recorder = AudioRecorder(audioDeviceClient: client)
        let fileURL = makeTempFile()
        let engine = AVAudioEngine()

        await recorder.setPreviousDefaultInputUIDForTest("old-device-uid")

        await recorder.rollbackStartup(didInstallTap: false, engine: engine, fileURL: fileURL)

        XCTAssertEqual(setDefaultInputDeviceCalls.snapshot(), ["old-device-uid"])
        let previousUID = await recorder.getPreviousDefaultInputUIDForTest()
        XCTAssertNil(previousUID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRollbackStartupStopsEngineAndDeletesFile() async {
        let client = AudioDeviceClient(
            availableInputDevices: { [] },
            setDefaultInputDevice: { _ in true },
            currentDefaultInputDeviceUID: { nil }
        )
        let recorder = AudioRecorder(audioDeviceClient: client)
        let fileURL = makeTempFile()
        let engine = AVAudioEngine()

        await recorder.rollbackStartup(didInstallTap: false, engine: engine, fileURL: fileURL)

        XCTAssertFalse(engine.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRollbackStartupRemovesTapWhenInstalled() async {
        let client = AudioDeviceClient(
            availableInputDevices: { [] },
            setDefaultInputDevice: { _ in true },
            currentDefaultInputDeviceUID: { nil }
        )
        let recorder = AudioRecorder(audioDeviceClient: client)
        let fileURL = makeTempFile()
        let engine = AVAudioEngine()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { _, _ in }

        await recorder.rollbackStartup(didInstallTap: true, engine: engine, fileURL: fileURL)

        XCTAssertFalse(engine.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - stopRecording restoration tests

    func testStopRecordingRestoresPreviousInputDevice() async {
        let setDefaultInputDeviceCalls = CallLog()
        let client = AudioDeviceClient(
            availableInputDevices: { [] },
            setDefaultInputDevice: { uid in
                setDefaultInputDeviceCalls.append(uid)
                return true
            },
            currentDefaultInputDeviceUID: { nil }
        )
        let recorder = AudioRecorder(audioDeviceClient: client)

        await recorder.setPreviousDefaultInputUIDForTest("old-device-uid")

        try? await recorder.stopRecording()

        XCTAssertEqual(setDefaultInputDeviceCalls.snapshot(), ["old-device-uid"])
        let previousUID = await recorder.getPreviousDefaultInputUIDForTest()
        XCTAssertNil(previousUID)
    }

    func testStopRecordingDoesNotRestoreWhenNoPreviousDevice() async {
        let setDefaultInputDeviceCalls = CallLog()
        let client = AudioDeviceClient(
            availableInputDevices: { [] },
            setDefaultInputDevice: { uid in
                setDefaultInputDeviceCalls.append(uid)
                return true
            },
            currentDefaultInputDeviceUID: { nil }
        )
        let recorder = AudioRecorder(audioDeviceClient: client)

        try? await recorder.stopRecording()

        XCTAssertTrue(setDefaultInputDeviceCalls.snapshot().isEmpty)
    }
}
