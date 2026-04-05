//
//  DeviceManager.swift
//  DFU-Tools
//
//  设备管理相关功能
//

import Foundation

// MARK: - 设备数据模型（使用 Codable 自动编码/解码）
struct Device: Codable, CustomStringConvertible {
    let type: String
    let ecid: String
    let udid: String
    let location: String
    let name: String
    var isInDFU: Bool = false  // DFU 模式状态
    
    // 芯片类型
    var chipType: String {
        // M 系列芯片
        if type.hasPrefix("MacBookPro17") { return "M" } // Only M1 Pro (13/14/16)-inch
        if type.hasPrefix("Macmini9") { return "M" } // Only M1 mini 
        if type.hasPrefix("MacBookAir10") { return "M" } // Only M1 Air

        // Mac13+ 为 M2/M3/M4 及未来型号
        if type.hasPrefix("Mac"),
           let num = Int(type.dropFirst(3).prefix(while: { $0.isNumber })),
           num >= 13 { return "M" }
        
        // iOS 设备
        if type.hasPrefix("iPhone") { return "A" }
        if type.hasPrefix("iPad") { return "A" }
        if type.hasPrefix("iPod") { return "A" }
        if type.hasPrefix("AppleTV") { return "A" }
        
        // iBridge T2 芯片
        if type.hasPrefix("iBridge") { return "T" }
        
        // 其他
        return "O"
    }
    
    // 自定义描述，用于显示
    var description: String {
        return "Type: \(type)\tECID: \(ecid)\tUDID: \(udid) Location: \(location) Name: \(name)"
    }
    
    // 预设设备数据已停用，保留历史样例仅供后续排查时参考。
    static let presetDevices: [Device] = []
    /*
    static let presetDevices: [Device] = [
        Device(type: "MacBookPro17,1", ecid: "0xA184002DA001E", udid: "N/A", location: "0x100000", name: "N/A"),
        Device(type: "iBridge2,21", ecid: "0x12C1822318026", udid: "N/A", location: "0x100000", name: "N/A"),
        Device(type: "MacBookPro17,1", ecid: "0xA184002DA002E", udid: "N/A", location: "0x100000", name: "N/A"),
        Device(type: "iBridge2,21", ecid: "0x12C1822318027", udid: "N/A", location: "0x100000", name: "N/A")
    ]
    */
}

// MARK: - 设备管理器
class DeviceManager {
    
    /// 预设的 DFU 状态映射（ECID -> isRestorable）
    /// 如果设备在预设列表中，将直接使用预设值而不调用 cfgutil
    static let presetDFUStatus: [String: Bool] = [
        "0xA184002DA001E": true,  // isRestorable = yes
        // 可以在这里添加更多预设设备
    ]
    
    /// 解析 cfgutil list 输出为设备数组
    static func parse(_ output: String) -> [Device] {
        output
            .components(separatedBy: .newlines)
            .compactMap { parseLine($0) }
    }
    
    /// 解析单行设备信息
    private static func parseLine(_ line: String) -> Device? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("Type:") else { return nil }
        
        var dict: [String: String] = [:]
        
        // 使用正则表达式匹配 "Key: Value" 模式
        let pattern = #"(\w+):\s+([^\t]+?)(?=\s+\w+:|$)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = trimmed as NSString
            regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: nsString.length))
                .forEach { match in
                    if match.numberOfRanges >= 3 {
                        let keyRange = match.range(at: 1)
                        let valueRange = match.range(at: 2)
                        if keyRange.location != NSNotFound && valueRange.location != NSNotFound {
                            dict[nsString.substring(with: keyRange)] = nsString.substring(with: valueRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
        }
        
        // 后备方案：按制表符分割
        if dict.isEmpty {
            trimmed.components(separatedBy: "\t").forEach { component in
                if let colonIndex = component.firstIndex(of: ":") {
                    let key = String(component[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(component[component.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty { dict[key] = value }
                }
            }
        }
        
        guard let type = dict["Type"], let ecid = dict["ECID"] else { return nil }
        return Device(
            type: type,
            ecid: ecid,
            udid: dict["UDID"] ?? "N/A",
            location: dict["Location"] ?? "N/A",
            name: dict["Name"] ?? "N/A",
            isInDFU: false
        )
    }
    
    /// 将设备数组格式化为显示字符串（使用 Codable 自动编码为 JSON）
    static func formatForDisplay(_ devices: [Device]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let jsonData = try? encoder.encode(devices),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        // 如果编码失败，使用描述字符串
        return devices.map { $0.description }.joined(separator: "\n")
    }
    
    /// 检查设备是否在 DFU 模式下
    /// - Parameters:
    ///   - device: 要检查的设备
    ///   - cfgutilPath: cfgutil 工具路径
    /// - Returns: 如果设备在 DFU 模式下返回 true，否则返回 false
    static func checkDFUStatus(_ device: Device, cfgutilPath: String) -> Bool {
        // 首先检查是否有预设值
        if let presetStatus = presetDFUStatus[device.ecid] {
            return presetStatus
        }
        
        let cfgutilDir = (cfgutilPath as NSString).deletingLastPathComponent
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cfgutilPath)
        process.arguments = ["-e", device.ecid, "get", "bootedState"]
        process.currentDirectoryPath = cfgutilDir
        
        // 设置环境变量，确保 cfgutil 能找到框架
        var environment = ProcessInfo.processInfo.environment
        let systemFrameworksPath = "/Applications/Apple Configurator.app/Contents/Frameworks"
        
        if FileManager.default.fileExists(atPath: systemFrameworksPath) {
            if let existingPath = environment["DYLD_FRAMEWORK_PATH"] {
                environment["DYLD_FRAMEWORK_PATH"] = "\(existingPath):\(systemFrameworksPath)"
            } else {
                environment["DYLD_FRAMEWORK_PATH"] = systemFrameworksPath
            }
        }
        process.environment = environment
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()  // 忽略错误输出
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                // bootedState 为 "dfu" 时表示设备在 DFU 模式
                return trimmed == "dfu"
            }
        } catch {
            // 如果执行失败，返回 false
            return false
        }
        
        return false
    }
}
