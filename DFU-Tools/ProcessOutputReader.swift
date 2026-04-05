//
//  ProcessOutputReader.swift
//  DFU-Tools
//
//  读取 helper 标准输出和错误输出。
//

import Foundation
import Darwin

class ProcessOutputReader {
    static func readAll(from fileDescriptor: Int32) -> Data {
        var outputData = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            let bytesRead = read(fileDescriptor, &buffer, bufferSize)
            if bytesRead <= 0 {
                break
            }
            outputData.append(contentsOf: buffer.prefix(Int(bytesRead)))
        }

        return outputData
    }

    static func readAll(from fileDescriptors: [Int32]) -> Data {
        var combinedData = Data()

        for fd in fileDescriptors {
            let data = readAll(from: fd)
            combinedData.append(data)
        }

        return combinedData
    }
}
