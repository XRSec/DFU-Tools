//
//  DeviceBindingManager.swift
//  DFU-Tools
//
//  预留的设备授权管理层。当前默认放行，仅保留后续启用授权校验的接口和设备信息采集。
//

import Foundation
import IOKit

extension Notification.Name {
    static let authorizationStatusChanged = Notification.Name("authorizationStatusChanged")
}

final class DeviceBindingManager {
    static let shared = DeviceBindingManager()

    private(set) var isAuthorized: Bool = true
    private var hasVerified = false

    // 通过环境变量或 UserDefaults 预留后续启用授权校验的开关。
    var isAuthorizationEnabled: Bool {
        if ProcessInfo.processInfo.environment["DFU_TOOLS_ENABLE_AUTH"]?.lowercased() == "true" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "DFU-Tools-EnableAuthorization")
    }

    private lazy var cachedSerialNumber: String? = hardwareSerialNumber()
    private lazy var cachedHardwareUUID: String? = hardwarePlatformUUID()
    private lazy var cachedModelIdentifier: String? = hardwareModelIdentifier()

    private init() {}

    func verifyAuthorization(forceCheck: Bool = false, completion: @escaping (Bool, String?) -> Void) {
        if hasVerified && !forceCheck {
            completion(isAuthorized, nil)
            return
        }

        hasVerified = true

        // 当前默认不启用授权校验，先保证功能可用，同时预留统一入口。
        guard isAuthorizationEnabled else {
            isAuthorized = true
            completion(true, L("Auth_Skipped"))
            return
        }

        // 后续如果真正启用授权，至少确保设备信息采集成功。
        guard cachedSerialNumber != nil,
              cachedHardwareUUID != nil,
              cachedModelIdentifier != nil else {
            isAuthorized = false
            completion(false, L("Auth_Device_Info_Failed"))
            return
        }

        isAuthorized = false
        completion(false, L("Auth_Not_Implemented"))
    }

    func deviceInfo() -> [String: String] {
        var info: [String: String] = [:]

        if let serial = cachedSerialNumber {
            info["serialNumber"] = serial
        }
        if let uuid = cachedHardwareUUID {
            info["hardwareUUID"] = uuid
        }
        if let model = cachedModelIdentifier {
            info["modelIdentifier"] = model
        }

        return info
    }

    private func hardwareSerialNumber() -> String? {
        platformProperty(kIOPlatformSerialNumberKey as String)
    }

    private func hardwarePlatformUUID() -> String? {
        platformProperty(kIOPlatformUUIDKey as String)
    }

    private func hardwareModelIdentifier() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }

        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else {
            return nil
        }

        return String(cString: model)
    }

    private func platformProperty(_ key: String) -> String? {
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }

        let platformExpert = IOServiceGetMatchingService(mainPort, IOServiceMatching("IOPlatformExpertDevice"))
        guard platformExpert > 0 else {
            return nil
        }
        defer { IOObjectRelease(platformExpert) }

        return IORegistryEntryCreateCFProperty(
            platformExpert,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }
}
