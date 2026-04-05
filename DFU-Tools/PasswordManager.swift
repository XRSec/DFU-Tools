//
//  PasswordManager.swift
//  DFU-Tools
//
//  与 micaixin 的交互方式保持接近，但不持久化管理员密码，也不引入额外密码算法。
//  这里只保留请求、验证、内存缓存与 IPSW 配置存储框架。
//

import Cocoa
import Foundation

private struct Config: Codable {
    var password: String?
    var ipsw: String?
}

class PasswordManager {
    static let shared = PasswordManager()

    private var cachedPassword: String?
    private var cachedIPSW: String?
    private let lockQueue = DispatchQueue(label: "com.dfutools.password")
    private let configFileName = "DFU-Tools.json"

    private var configFilePath: URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupportURL.appendingPathComponent(configFileName)
    }

    private init() {
        checkStoredConfig()
    }

    private func loadConfig() -> Config? {
        guard let filePath = configFilePath else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: filePath) else {
            return nil
        }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    private func saveConfig(_ config: Config) -> Bool {
        guard let filePath = configFilePath else {
            return false
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(config) else {
            return false
        }

        do {
            try data.write(to: filePath)
            return true
        } catch {
            log(L("Password_Config_Save_Failed", error.localizedDescription))
            return false
        }
    }

    private func checkStoredConfig() {
        lockQueue.async {
            guard let config = self.loadConfig() else {
                log(L("Password_Config_Not_Found"))
                return
            }

            guard let filePath = self.configFilePath else {
                log(L("Password_Config_Path_Error"))
                return
            }

            log(false, L("Password_Config_Detected"))
            log(false, L("Password_Config_Location", filePath.path))

            if let password = config.password, !password.isEmpty {
                log(false, L("Password_Config_Cached"))
                self.cachedPassword = password
            }

            if let ipsw = config.ipsw, !ipsw.isEmpty {
                self.cachedIPSW = ipsw
            }
        }
    }

    func requestPasswordIfNeeded() -> String? {
        return lockQueue.sync {
            if let password = cachedPassword {
                log(false, L("Password_Config_Trying"))
                if verifyPassword(password) {
                    log(false, L("Password_Config_Verify_Success"))
                    return password
                } else {
                    log(L("Password_Config_Expired"))
                    cachedPassword = nil
                }
            }

            if let config = loadConfig(),
               let storedPassword = config.password,
               !storedPassword.isEmpty {
                log(false, L("Password_Config_Trying"))
                if verifyPassword(storedPassword) {
                    log(false, L("Password_Config_Verify_Success"))
                    cachedPassword = storedPassword
                    return storedPassword
                } else {
                    log(L("Password_Config_Verify_Failed"))
                    var newConfig = config
                    newConfig.password = nil
                    _ = saveConfig(newConfig)
                }
            }

            log(false, L("Password_Request"))
            return requestPassword()
        }
    }

    private func requestPassword(isRetry: Bool = false) -> String? {
        var password: String?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            let message = L("Password_Required")
            let informativeText = isRetry ? L("Password_Enter_Retry") : L("Password_Enter")
            let alertStyle: NSAlert.Style = isRetry ? .warning : .informational

            AlertManager.shared.showPasswordDialog(
                message: message,
                informativeText: informativeText,
                alertStyle: alertStyle
            ) { result in
                password = result
                semaphore.signal()
            }
        }

        semaphore.wait()

        guard let pwd = password, !pwd.isEmpty else {
            return nil
        }

        if verifyPassword(pwd) {
            cachedPassword = pwd
            var config = loadConfig() ?? Config()
            config.password = pwd
            _ = saveConfig(config)
            log(false, L("Password_Verify_Success"))
            return pwd
        }

        log(L("Password_Verify_Failed"))
        return requestPassword(isRetry: true)
    }

    private func verifyPassword(_ password: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-S", "true"]

        let inputPipe = Pipe()
        task.standardInput = inputPipe
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            log(L("Password_Verify_Process_Failed", error.localizedDescription))
            return false
        }

        if let passwordData = (password + "\n").data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(passwordData)
            inputPipe.fileHandleForWriting.closeFile()
        }

        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    func executeWithSudo(command: String, _ arguments: [String], cwd: String) -> (status: Int32, output: Data) {
        guard let password = requestPasswordIfNeeded() else {
            return (status: -1, output: Data())
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-S", command] + arguments
        task.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardInput = inputPipe
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            log(L("Password_Execute_Process_Failed", error.localizedDescription))
            return (status: -1, output: Data())
        }

        if let passwordData = (password + "\n").data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(passwordData)
            inputPipe.fileHandleForWriting.closeFile()
        }

        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if task.terminationStatus != 0,
           let errorString = String(data: errorData, encoding: .utf8),
           errorString.contains("Sorry, try again") {
            log(L("Password_Config_Expired"))
            clearCachedPassword()
        }

        var combinedData = outputData
        if !errorData.isEmpty {
            combinedData.append(errorData)
        }

        return (status: task.terminationStatus, output: combinedData)
    }

    func clearPassword() {
        lockQueue.sync {
            cachedPassword = nil
            var config = loadConfig() ?? Config()
            config.password = nil
            _ = saveConfig(config)
            log(L("Password_Cache_Cleared"))
        }
    }

    func clearCachedPassword() {
        lockQueue.sync {
            cachedPassword = nil
            log(false, L("Password_Memory_Cache_Cleared"))
        }
    }

    func ipswPath() -> String? {
        return lockQueue.sync {
            if let ipsw = cachedIPSW {
                return ipsw
            }

            if let config = loadConfig(),
               let ipsw = config.ipsw,
               !ipsw.isEmpty {
                cachedIPSW = ipsw
                return ipsw
            }

            return nil
        }
    }

    func updateIPSW(_ ipsw: String?) {
        lockQueue.sync {
            cachedIPSW = ipsw
            var config = loadConfig() ?? Config()
            config.ipsw = ipsw
            _ = saveConfig(config)
        }
    }

    deinit {
        clearCachedPassword()
    }
}
