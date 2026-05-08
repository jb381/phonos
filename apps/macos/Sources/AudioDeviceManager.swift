import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AudioDeviceManager {
    static func availableInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        ) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &devices
        ) == noErr else { return [] }

        var result: [AudioDevice] = []

        for deviceID in devices {
            guard deviceHasInputChannels(deviceID) else { continue }
            guard let name = getDeviceName(deviceID) else { continue }
            let uid = getDeviceUID(deviceID) ?? ""
            result.append(AudioDevice(id: uid, name: name))
        }

        return result
    }

    @discardableResult
    static func setDefaultInputDevice(uid: String) -> Bool {
        guard let deviceID = deviceIDForUID(uid) else { return false }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var id = deviceID
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        ) == noErr
    }

    static func currentDefaultInputDeviceUID() -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceID
        ) == noErr else { return nil }

        return getDeviceUID(deviceID)
    }

    // MARK: - Private Helpers

    private static func deviceHasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize
        ) == noErr else { return false }

        return dataSize > 0
    }

    private static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &name
        ) == noErr else { return nil }

        return name?.takeRetainedValue() as String?
    }

    private static func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &uid
        ) == noErr else { return nil }

        return uid?.takeRetainedValue() as String?
    }

    private static func deviceIDForUID(_ uid: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        ) == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &devices
        ) == noErr else { return nil }

        for deviceID in devices {
            if getDeviceUID(deviceID) == uid {
                return deviceID
            }
        }

        return nil
    }
}
