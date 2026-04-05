//
//  LogManager.swift
//  DFU-Tools
//
//  日志管理器，将所有日志输出到 Logs Scroll View
//

import Foundation
import Cocoa

class LogManager {
    static let shared = LogManager()
    
    private var textView: NSTextView?
    private let logQueue = DispatchQueue(label: "com.xrsec.dfu-tools.log", qos: .utility)
    private var logBuffers: [String] = []
    private let maxBufferSize = 1000  // 最大缓冲行数
    
    private init() {
        // 初始化日志管理器
    }
    
    /// 设置日志输出目标
    func configureTextView(_ textView: NSTextView) {
        self.textView = textView
        
        // 输出缓冲的日志
        if !logBuffers.isEmpty {
            let bufferedLogs = logBuffers.joined(separator: "")
            logBuffers.removeAll()
            appendToTextView(bufferedLogs)
        }
    }
    
    /// 输出日志到 textView 和终端（用户可见信息）
    /// - Parameters:
    ///   - showInView: 是否显示在 Logs Scroll View（默认 true）
    ///   - message: 日志消息
    func log(_ showInView: Bool = true, _ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        
        // 同步输出到控制台（终端）
        print(logMessage, terminator: "")
        
        // 根据参数决定是否输出到 textView
        if showInView {
            appendToTextView(logMessage)
        }
    }
    
    /// 追加文本到 textView
    private func appendToTextView(_ text: String) {
        logQueue.async { [weak self] in
            guard let textView = self?.textView else {
                // 如果 textView 还未设置，先缓冲日志
                self?.logBuffers.append(text)
                // 限制缓冲区大小
                if let buffers = self?.logBuffers, buffers.count > self?.maxBufferSize ?? 1000 {
                    self?.logBuffers.removeFirst(buffers.count - (self?.maxBufferSize ?? 1000))
                }
                return
            }
            
            DispatchQueue.main.async {
                let currentText = textView.string
                textView.string = currentText + text
                textView.scrollToEndOfDocument(nil)
            }
        }
    }
    
    /// 清空日志
    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.textView?.string = ""
        }
    }
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - 全局日志函数
/// 输出日志到 Logs Scroll View（只接受 String，避免与系统 log 函数冲突）
/// - Parameter message: 日志消息
func log(_ message: String) {
    LogManager.shared.log(true, message)
}

/// 输出日志到 Logs Scroll View
/// - Parameters:
///   - showInView: 是否显示在 Logs Scroll View
///   - message: 日志消息
func log(_ showInView: Bool, _ message: String) {
    LogManager.shared.log(showInView, message)
}

/// 输出日志到 Logs Scroll View（带格式化）
/// - Parameters:
///   - format: 格式化字符串
///   - arguments: 参数
func log(_ format: String, _ arguments: CVarArg...) {
    let message = String(format: format, arguments: arguments)
    LogManager.shared.log(true, message)
}

/// 输出日志到 Logs Scroll View（带格式化）
/// - Parameters:
///   - showInView: 是否显示在 Logs Scroll View
///   - format: 格式化字符串
///   - arguments: 参数
func log(_ showInView: Bool, _ format: String, _ arguments: CVarArg...) {
    let message = String(format: format, arguments: arguments)
    LogManager.shared.log(showInView, message)
}
