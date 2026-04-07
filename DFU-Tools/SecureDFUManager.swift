//
//  SecureDFUManager.swift
//  DFU-Tools
//
//  SocketXOR helper 通信管理器。父进程通过 sudo 拉起独立 helper，
//  再使用 Unix Domain Socket 发送命令请求。
//

import Foundation
import Darwin
import Security

@_silgen_name("fork")
private func fork() -> pid_t

@_silgen_name("execv")
private func execv(_ path: UnsafePointer<CChar>, _ argv: UnsafePointer<UnsafeMutablePointer<CChar>?>) -> Int32

@_silgen_name("strdup")
private func strdup(_ s: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("pipe")
private func pipe(_ fildes: UnsafeMutablePointer<Int32>) -> Int32

@_silgen_name("dup2")
private func dup2(_ fildes: Int32, _ fildes2: Int32) -> Int32

@_silgen_name("write")
private func write(_ fildes: Int32, _ buf: UnsafeRawPointer, _ nbyte: Int) -> ssize_t

@_silgen_name("waitpid")
private func waitpid(_ pid: pid_t, _ stat_loc: UnsafeMutablePointer<Int32>?, _ options: Int32) -> pid_t

private let secureSTDIN: Int32 = 0
private let secureSTDOUT: Int32 = 1
private let secureSTDERR: Int32 = 2

enum SecureDFUCommand: String {
    case serial
    case debugusb
    case reboot
    case rebootSerial
    case rebootDebugUSB
    case dfu
    case nop
    case actions
    case actionInfo

    var requestCommand: String {
        switch self {
        case .serial:
            return "serial"
        case .debugusb:
            return "debugusb"
        case .reboot:
            return "reboot"
        case .rebootSerial:
            return "reboot:serial"
        case .rebootDebugUSB:
            return "reboot:debugusb"
        case .dfu:
            return "dfu"
        case .nop:
            return "nop"
        case .actions:
            return "actions"
        case .actionInfo:
            return "actionInfo"
        }
    }
}

final class SecureDFUManager {
    static let shared = SecureDFUManager()

    private let socketNamePrefix = "dfut"
    private let sessionKeySize = 32
    private let helperResourceName = "DFUToolsHelper"

    private init() {}

    func executeCommand(_ command: SecureDFUCommand, actionId: UInt16? = nil) throws -> (status: Int32, output: String) {
        let sessionKey = generateSessionKey()
        let socketPath = createSocketPath()
        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw createError("Failed to create socket")
        }
        defer {
            close(socketFd)
            unlink(socketPath)
        }

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw createError("Socket path too long")
        }
        _ = pathBytes.withUnsafeBytes { bytes in
            memcpy(&addr.sun_path, bytes.baseAddress, pathBytes.count)
        }

        unlink(socketPath)

        let addrLen = socklen_t(MemoryLayout.size(ofValue: addr))
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFd, sockaddrPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            throw createError("Failed to bind socket: \(String(cString: strerror(errno)))")
        }

        guard listen(socketFd, 1) == 0 else {
            throw createError("Failed to listen on socket: \(String(cString: strerror(errno)))")
        }

        chmod(socketPath, 0o600)

        guard let password = PasswordManager.shared.requestPasswordIfNeeded() else {
            throw createError(L("Password_Required"))
        }

        guard let helperPath = Bundle.main.url(forResource: helperResourceName, withExtension: nil)?.path else {
            throw createError(L("Helper_Not_Found"))
        }

        var stdinPipe: [Int32] = [0, 0]
        guard pipe(&stdinPipe) == 0 else {
            throw createError("Failed to create stdin pipe")
        }

        var stdoutPipe: [Int32] = [0, 0]
        guard pipe(&stdoutPipe) == 0 else {
            closePipes([stdinPipe[0], stdinPipe[1]])
            throw createError("Failed to create stdout pipe")
        }

        var stderrPipe: [Int32] = [0, 0]
        guard pipe(&stderrPipe) == 0 else {
            closePipes([stdinPipe[0], stdinPipe[1], stdoutPipe[0], stdoutPipe[1]])
            throw createError("Failed to create stderr pipe")
        }

        let pid = fork()
        guard pid >= 0 else {
            closePipes([stdinPipe[0], stdinPipe[1], stdoutPipe[0], stdoutPipe[1], stderrPipe[0], stderrPipe[1]])
            throw createError("Failed to fork")
        }

        if pid == 0 {
            close(stdinPipe[1])
            guard dup2(stdinPipe[0], secureSTDIN) >= 0 else { exit(1) }
            close(stdinPipe[0])

            close(stdoutPipe[0])
            guard dup2(stdoutPipe[1], secureSTDOUT) >= 0 else { exit(1) }
            close(stdoutPipe[1])

            close(stderrPipe[0])
            guard dup2(stderrPipe[1], secureSTDERR) >= 0 else { exit(1) }
            close(stderrPipe[1])

            let sudoPath = "/usr/bin/sudo"
            let args = [sudoPath, "-S", helperPath, socketPath]
            var argv = args.map { strdup($0) }
            argv.append(nil)

            _ = execv(sudoPath, &argv)
            exit(1)
        }

        close(stdinPipe[0])
        close(stdoutPipe[1])
        close(stderrPipe[1])

        let passwordData = (password + "\n").data(using: .utf8) ?? Data()
        var writeSuccess = false
        passwordData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            let written = write(stdinPipe[1], baseAddress, passwordData.count)
            writeSuccess = (written == passwordData.count)
        }
        close(stdinPipe[1])

        if !writeSuccess {
            log(false, "Warning: Password write may be incomplete")
        }

        var clientAddr = sockaddr_un()
        var clientAddrLen = socklen_t(MemoryLayout.size(ofValue: clientAddr))
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(socketFd, sockaddrPtr, &clientAddrLen)
            }
        }
        guard clientFd >= 0 else {
            closePipes([stdoutPipe[0], stderrPipe[0]])
            throw createError("Failed to accept connection: \(String(cString: strerror(errno)))")
        }
        defer { close(clientFd) }

        try sendData(sessionKey, to: clientFd)

        let requestPayload = try buildRequestPayload(command: command, actionId: actionId)
        let encryptedRequest = encrypt(data: requestPayload, using: sessionKey)
        try sendData(encryptedRequest, to: clientFd)
        shutdown(clientFd, SHUT_WR)

        var waitStatus: Int32 = 0
        let waitResult = waitpid(pid, &waitStatus, 0)
        let exitStatus: Int32 = waitResult < 0 ? -1 : ((waitStatus & 0xff00) >> 8)

        let outputData = ProcessOutputReader.readAll(from: [stdoutPipe[0], stderrPipe[0]])
        closePipes([stdoutPipe[0], stderrPipe[0]])

        let output = String(data: outputData, encoding: .utf8) ?? ""
        return (status: exitStatus, output: output)
    }

    private func createError(_ message: String) -> NSError {
        NSError(domain: "SecureDFUManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func closePipes(_ pipes: [Int32]) {
        pipes.forEach { close($0) }
    }

    private func generateSessionKey() -> Data {
        var keyData = Data(count: sessionKeySize)
        let result = keyData.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, sessionKeySize, baseAddress)
        }
        guard result == errSecSuccess else {
            fatalError("Failed to generate session key")
        }
        return keyData
    }

    private func createSocketPath() -> String {
        let processId = ProcessInfo.processInfo.processIdentifier
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return "/tmp/\(socketNamePrefix).\(processId).\(timestamp).sock"
    }

    private func applyRollingXOR(_ buf: inout [UInt8], key: [UInt8]) {
        var acc: UInt8 = 0xA5
        for i in 0..<buf.count {
            acc = (acc &+ key[i % key.count]) ^ UInt8(i & 0xff)
            buf[i] ^= acc
        }
    }

    private func encrypt(data: Data, using key: Data) -> Data {
        var encrypted = Array(data)
        applyRollingXOR(&encrypted, key: Array(key))
        return Data(encrypted)
    }

    private func sendData(_ data: Data, to socketFd: Int32) throws {
        var length = UInt32(data.count).bigEndian
        let lengthData = withUnsafeBytes(of: &length) { Data($0) }

        try writeAll(lengthData, to: socketFd)
        try writeAll(data, to: socketFd)
    }

    private func writeAll(_ data: Data, to socketFd: Int32) throws {
        var totalSent = 0
        while totalSent < data.count {
            var sent: ssize_t = 0
            data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                sent = send(socketFd, baseAddress + totalSent, data.count - totalSent, 0)
            }
            if sent <= 0 {
                throw createError("Failed to send data")
            }
            totalSent += Int(sent)
        }
    }

    private func buildRequestPayload(command: SecureDFUCommand, actionId: UInt16?) throws -> Data {
        let request: String

        switch command {
        case .actionInfo:
            guard let actionId else {
                throw createError("actionInfo requires actionId")
            }
            request = "\(command.requestCommand):0x\(String(actionId, radix: 16, uppercase: false))"
        default:
            request = command.requestCommand
        }

        return Data(request.utf8)
    }
}
