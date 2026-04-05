//
//  USBDeviceMonitor.swift
//  DFU-Tools
//
//  USB 设备监听器，使用 IOKit 官方 API
//

import Foundation
import IOKit
import IOKit.usb

class USBDeviceMonitor {
    
    // 回调闭包类型
    typealias DeviceChangeCallback = () -> Void
    
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var callback: DeviceChangeCallback?
    private var isMonitoring = false
    private var isInitializing = true
    
    // 防抖相关
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 2.0
    
    /// 开始监听 USB 设备事件
    /// - Parameter callback: 当 USB 设备连接或断开时调用的回调
    func startMonitoring(callback: @escaping DeviceChangeCallback) {
        guard !isMonitoring else {
            log(L("USB_Monitor_Already_Running"))
            return
        }
        
        self.callback = callback
        
        // 创建通知端口
        notificationPort = IONotificationPortCreate(kIOMasterPortDefault)
        guard let notificationPort = notificationPort else {
            log(L("USB_Monitor_Create_Port_Failed"))
            return
        }
        
        // 将通知端口添加到主运行循环
        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        
        // 注册设备添加通知（每次调用需要新的匹配字典，因为会被消耗）
        var addedIterator: io_iterator_t = 0
        let addedResult = IOServiceAddMatchingNotification(
            notificationPort,
            kIOMatchedNotification,
            IOServiceMatching(kIOUSBDeviceClassName),
            Self.deviceAddedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &addedIterator
        )
        
        if addedResult == KERN_SUCCESS {
            self.addedIterator = addedIterator
            // 必须立即遍历迭代器以清空已存在的设备，否则后续通知不会触发
            Self.deviceAddedCallback(Unmanaged.passUnretained(self).toOpaque(), addedIterator)
        } else {
            log(L("USB_Monitor_Register_Added_Failed", Int(addedResult)))
        }
        
        // 注册设备移除通知（需要新的匹配字典）
        var removedIterator: io_iterator_t = 0
        let removedResult = IOServiceAddMatchingNotification(
            notificationPort,
            kIOTerminatedNotification,
            IOServiceMatching(kIOUSBDeviceClassName),
            Self.deviceRemovedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &removedIterator
        )
        
        if removedResult == KERN_SUCCESS {
            self.removedIterator = removedIterator
            // 必须立即遍历迭代器以清空已移除的设备，否则后续通知不会触发
            Self.deviceRemovedCallback(Unmanaged.passUnretained(self).toOpaque(), removedIterator)
        } else {
            log(L("USB_Monitor_Register_Removed_Failed", Int(removedResult)))
        }
        
        isMonitoring = true
        // 初始化完成，允许后续回调触发
        isInitializing = false
        log(L("USB_Monitor_Started"))
    }
    
    /// 停止监听 USB 设备事件
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // 销毁迭代器
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
        
        // 销毁通知端口
        if let notificationPort = notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        
        callback = nil
        isMonitoring = false
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        log(L("USB_Monitor_Stopped"))
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - 私有方法
    
    /// 防抖触发回调
    private func scheduleCallback() {
        // 取消之前的待执行任务
        debounceWorkItem?.cancel()
        
        // 创建新的延迟任务
        let workItem = DispatchWorkItem { [weak self] in
            self?.callback?()
        }
        debounceWorkItem = workItem
        
        // 2 秒后执行
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    /// 设备添加回调（C 函数）
    private static let deviceAddedCallback: IOServiceMatchingCallback = { context, iterator in
        guard let context = context else { return }
        
        let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        
        // 遍历所有匹配的设备
        var service: io_service_t = 0
        while true {
            service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            
            // 获取设备信息
            if let deviceName = deviceName(service: service) {
                log(L("USB_Device_Detected", deviceName))
            } else {
                log(L("USB_Device_Detected_Unknown"))
            }
            
            // 释放服务对象
            IOObjectRelease(service)
        }
        
        // 在主线程调用回调（跳过初始化阶段的回调，使用防抖）
        if !monitor.isInitializing {
            DispatchQueue.main.async {
                monitor.scheduleCallback()
            }
        }
    }
    
    /// 设备移除回调（C 函数）
    private static let deviceRemovedCallback: IOServiceMatchingCallback = { context, iterator in
        guard let context = context else { return }
        
        let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        
        // 遍历所有匹配的设备
        var service: io_service_t = 0
        while true {
            service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            
            // 获取设备信息
            if let deviceName = deviceName(service: service) {
                log(L("USB_Device_Disconnected", deviceName))
            } else {
                log(L("USB_Device_Disconnected_Unknown"))
            }
            
            // 释放服务对象
            IOObjectRelease(service)
        }
        
        // 在主线程调用回调（跳过初始化阶段的回调，使用防抖）
        if !monitor.isInitializing {
            DispatchQueue.main.async {
                monitor.scheduleCallback()
            }
        }
    }
    
    /// 获取设备名称（用于调试）
    private static func deviceName(service: io_service_t) -> String? {
        // 尝试从 IORegistry 获取产品名称
        if let name = IORegistryEntryCreateCFProperty(
            service,
            "USB Product Name" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeUnretainedValue() as? String {
            return name
        }
        
        // 尝试获取厂商名称
        if let vendor = IORegistryEntryCreateCFProperty(
            service,
            "USB Vendor Name" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeUnretainedValue() as? String {
            return vendor
        }
        
        return nil
    }
}
