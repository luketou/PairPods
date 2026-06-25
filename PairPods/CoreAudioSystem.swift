//
//  CoreAudioSystem.swift
//  PairPods
//

import CoreAudio
import Foundation

struct CoreAudioSystem: AudioSystemQuerying, AudioSystemCommanding {
    func fetchAllAudioDevices() async throws -> [AudioDevice] {
        let deviceIDs = try fetchAllAudioDeviceIDs()
        return await withTaskGroup(of: AudioDevice?.self) { group in
            for deviceID in deviceIDs {
                group.addTask {
                    await AudioDevice(deviceID: deviceID)
                }
            }
            var devices: [AudioDevice] = []
            for await device in group {
                if let device {
                    devices.append(device)
                }
            }
            return devices
        }
    }

    func fetchDefaultOutputDevice() async -> (AudioDevice?, AudioDeviceID?) {
        guard let defaultDeviceID = findDefaultAudioDeviceID() else {
            return (nil, nil)
        }
        let device = await AudioDevice(deviceID: defaultDeviceID)
        return (device, defaultDeviceID)
    }

    func fetchDeviceID(deviceUID: String) async -> AudioDeviceID? {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid = deviceUID as CFString
        var deviceID = AudioDeviceID(0)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            systemObject, &address,
            UInt32(MemoryLayout<CFString>.size), &uid,
            &propSize, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    func createAggregateDevice(name: String, uid: String,
                               masterUID: String, subDeviceUIDs: [String]) async throws -> AudioDeviceID
    {
        logDebug("Creating aggregate device")
        let subDeviceList: [[String: Any]] = subDeviceUIDs.map { uid in
            if uid == masterUID {
                [kAudioSubDeviceUIDKey: uid]
            } else {
                [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceDriftCompensationKey as String: 1]
            }
        }
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceList,
            kAudioAggregateDeviceMasterSubDeviceKey: masterUID,
            kAudioAggregateDeviceIsStackedKey: 0, // 0 = multi-output mirror mode (same audio to all devices)
        ]

        var aggregateDevice: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregateDevice)
        guard status == noErr else {
            throw AppError.operationError("Failed to create aggregate device. Status: \(status)")
        }

        logInfo("Created aggregate device with ID: \(aggregateDevice)")
        return aggregateDevice
    }

    func destroyAggregateDevice(deviceID: AudioDeviceID) async throws {
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        guard status == noErr else {
            throw AppError.operationError("Failed to destroy aggregate device. Status: \(status)")
        }
    }

    func prepareForBluetoothSharing(outputDeviceUIDs: [String]) async {
        let excludedPhysicalDevices = Set(
            outputDeviceUIDs.map(AudioDevice.physicalDeviceIdentifier(forUID:))
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var inputAddress = systemObject.getPropertyAddress(selector: kAudioHardwarePropertyDefaultInputDevice)
        var defaultInputID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            systemObject,
            &inputAddress,
            0,
            nil,
            &size,
            &defaultInputID
        ) == noErr,
            let defaultInputUID = defaultInputID.getStringProperty(selector: kAudioDevicePropertyDeviceUID),
            excludedPhysicalDevices.contains(AudioDevice.physicalDeviceIdentifier(forUID: defaultInputUID))
        else {
            return
        }

        guard let deviceIDs = try? fetchAllAudioDeviceIDs(),
              let builtInInputID = deviceIDs.first(where: { deviceID in
                  guard deviceID.getUInt32Property(selector: kAudioDevicePropertyTransportType) ==
                      kAudioDeviceTransportTypeBuiltIn
                  else {
                      return false
                  }
                  return (deviceID.getStreamConfiguration(scope: kAudioObjectPropertyScopeInput)?.mNumberBuffers ?? 0) > 0
              })
        else {
            logWarning("Bluetooth microphone is active, but no built-in input device was available")
            return
        }

        var newInputID = builtInInputID
        let status = AudioObjectSetPropertyData(
            systemObject,
            &inputAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &newInputID
        )
        if status == noErr {
            logInfo("Moved default input to the built-in microphone to keep shared devices in A2DP mode")
        } else {
            logWarning("Failed to move default input away from shared Bluetooth device. Status: \(status)")
        }
    }

    func setDefaultOutputDevice(deviceID: AudioDeviceID) async throws {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        for selector in [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ] {
            var propertyAddress = systemObject.getPropertyAddress(selector: selector)
            var mutableDeviceID = deviceID
            let status = AudioObjectSetPropertyData(
                systemObject,
                &propertyAddress,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &mutableDeviceID
            )
            guard status == noErr else {
                throw AppError.operationError(
                    "Failed to set output route \(selector). Status: \(status)"
                )
            }
        }
    }

    func setSampleRate(on deviceID: AudioDeviceID, to sampleRate: Double) -> Bool {
        deviceID.setSampleRate(sampleRate)
    }

    // MARK: - Private Helpers

    private func fetchAllAudioDeviceIDs() throws -> [AudioDeviceID] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var propertyAddress = systemObject.getPropertyAddress(selector: kAudioHardwarePropertyDevices)

        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(systemObject, &propertyAddress, 0, nil, &propertySize)
        guard status == noErr else {
            throw AppError.operationError("Unable to get property data size for audio devices. Status: \(status)")
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let getStatus = AudioObjectGetPropertyData(systemObject, &propertyAddress, 0, nil, &propertySize, &deviceIDs)
        guard getStatus == noErr else {
            throw AppError.operationError("Unable to get audio device IDs. Status: \(getStatus)")
        }

        return deviceIDs
    }

    private func findDefaultAudioDeviceID() -> AudioDeviceID? {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var defaultDeviceID = AudioDeviceID()
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = systemObject.getPropertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice)

        let status = AudioObjectGetPropertyData(systemObject, &propertyAddress, 0, nil, &propertySize, &defaultDeviceID)
        return status == noErr ? defaultDeviceID : nil
    }
}
