//
//  ViewController.swift
//  DFU-Tools
//
//  Created by Wayne Bonnici on 27/04/2022.
//

import Cocoa
import Foundation
import Combine

enum STError: Error {
    case noInit
    case authCancelled
    case invalidAuth
}

class ViewController: NSViewController {
    @IBOutlet weak var deviceTableView: NSTableView!  // 设备列表表格视图
    @IBOutlet weak var dfuButton: NSButton!
    @IBOutlet weak var rebootButton: NSButton!
    @IBOutlet weak var restoreButton: NSButton!
    @IBOutlet weak var reviveButton: NSButton!
    @IBOutlet var outputTextView: NSTextView!
    @IBOutlet weak var wechatImageView1: NSImageView!
    @IBOutlet weak var wechatImageView2: NSImageView!
    @IBOutlet weak var wechatPayImageView: NSImageView!
    @IBOutlet weak var useIPSWCheckbox: NSButton!
    @IBOutlet weak var selectIPSWButton: NSButton!
    @IBOutlet weak var ipswPathLabel: NSTextField!
    @IBOutlet weak var ipswLinkButton: NSButton!
    @IBOutlet weak var mdmLinkButton: NSButton!
    @IBOutlet weak var clearLogsButton: NSButton!
    @IBOutlet weak var labelKefu: NSTextField!
    @IBOutlet weak var labelDev: NSTextField!
    @IBOutlet weak var labelPay: NSTextField!
    @IBOutlet weak var deviceLabel: NSTextField!
    @IBOutlet weak var deviceListLabel: NSTextField!
    
    private var selectedIPSWPath: String?
    private var devices: [Device] = []  // 存储设备列表
    private var usbMonitor: USBDeviceMonitor?  // USB 设备监听器
    private var cancellables = Set<AnyCancellable>()  // Combine 订阅管理
    
    typealias STReturn = (status: Int32, error: OSStatus, data: Data)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        
        var sysinfo: utsname = utsname()
        let exitCode = uname(&sysinfo)
        guard exitCode == EXIT_SUCCESS else {
            exit(1)
        }
        let machine = withUnsafePointer(to: &sysinfo.machine) { 
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(validatingUTF8: ptr)
            }
        }
        guard let machine = machine else {
            exit(1)
        }
#if !DEBUG
        if machine != "arm64" {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = L("Error_Unsupported_Mac")
                alert.addButton(withTitle: L("Menu_Quit"))
                if alert.runModal() == .alertFirstButtonReturn {
                    exit(1)
                }
            }
        }
#endif
        
        // 确保复选框按钮正确显示（复选框使用 .onOff 类型）
        useIPSWCheckbox?.setButtonType(.onOff)
        useIPSWCheckbox?.imagePosition = .imageLeft
        
        // 从配置文件读取 IPSW 路径
        loadIPSWFromConfig()
        
        updateIPSWControls()
        
        // 设置设备列表表格视图
        setupDeviceTableView()
        
        // 设置窗口大小限制（固定为 550x690，包括标题栏）
        if let window = view.window {
            let windowSize = NSSize(width: 550, height: 690)
            window.minSize = windowSize
            window.maxSize = windowSize
        }
        
        // 初始化日志管理器
        LogManager.shared.configureTextView(outputTextView)
        
        // 初始化并启动 USB 设备监听器
        setupUSBMonitor()
        
        // 为 ipswPathLabel 添加点击手势
        setupIPSWPathLabelClick()
        
        // 初始化 UI 元素的本地化文本
        updateLocalization()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthorizationStatusChanged),
            name: .authorizationStatusChanged,
            object: nil
        )
        updateSecureButtonStates()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // 确保窗口大小固定
        if let window = view.window {
            let windowSize = NSSize(width: 550, height: 690)
            window.minSize = windowSize
            window.maxSize = windowSize
        }
        // 初始化 UI 元素的本地化文本
        updateLocalization()
        // 窗口显示时刷新设备列表（软件启动时获取一次数据）
        refreshDeviceList()
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        // 停止 USB 监听器
        usbMonitor?.stopMonitoring()
        NotificationCenter.default.removeObserver(self, name: .authorizationStatusChanged, object: nil)
    }
    
    // MARK: - 本地化初始化
    
    /// 初始化所有 UI 元素的本地化文本
    /// 注意：语言切换时通过重建窗口实现，此方法仅在视图初始化时调用
    private func updateLocalization() {
        // 更新按钮
        dfuButton?.title = L("Button_DFU")
        rebootButton?.title = L("Button_Reboot")
        restoreButton?.title = L("Button_Restore")
        reviveButton?.title = L("Button_Revive")
        selectIPSWButton?.title = L("Button_Select_IPSW")
        ipswLinkButton?.title = L("Button_Get_IPSW")
        mdmLinkButton?.title = L("Button_Bypass_MDM")
        useIPSWCheckbox?.title = L("Button_Use_IPSW")
        // clearLogsButton 保持原始标题 "X"（清除符号，无需本地化）
        
        // 更新标签
        if let label = labelKefu {
            label.stringValue = L("Label_Customer_Service")
        } else {
            log(false, "labelKefu is nil - not connected in Storyboard")
        }
        
        if let label = labelDev {
            label.stringValue = L("Label_Developer")
        } else {
            log(false, "labelDev is nil - not connected in Storyboard")
        }
        
        if let label = labelPay {
            label.stringValue = L("Label_Donate")
        } else {
            log(false, "labelPay is nil - not connected in Storyboard")
        }
        
        if let label = deviceLabel {
            label.stringValue = L("Label_Logs")
        } else {
            log(false, "deviceLabel is nil - not connected in Storyboard")
        }
        
        if let label = deviceListLabel {
            label.stringValue = L("Label_Device_List")
        } else {
            log(false, "deviceListLabel is nil - not connected in Storyboard")
        }
        
        // 更新表格列标题
        if let count = deviceTableView?.tableColumns.count, count >= 3 {
            deviceTableView?.tableColumns[0].headerCell.stringValue = L("Device_Status_DFU")
            deviceTableView?.tableColumns[1].headerCell.stringValue = L("Device_Chip_Type")
            deviceTableView?.tableColumns[2].headerCell.stringValue = L("Device_List_Header")
        }
        
        // 更新 IPSW 相关文本（仅在显示默认文本时更新）
        let noFileText = L("IPSW_No_File_Selected")
        if ipswPathLabel?.stringValue.isEmpty == true || 
           ipswPathLabel?.stringValue == noFileText ||
           (ipswPathLabel?.stringValue.contains("IPSW_No_File_Selected") == true) {
            ipswPathLabel?.stringValue = noFileText
        }
        
        // 刷新表格视图
        deviceTableView?.reloadData()
    }
    
    // MARK: - USB 设备监听
    
    /// 设置 USB 设备监听器
    private func setupUSBMonitor() {
        usbMonitor = USBDeviceMonitor()
        
        // 启动监听，当 USB 设备连接或断开时刷新设备列表
        usbMonitor?.startMonitoring { [weak self] in
            // USB 设备事件发生时，延迟一小段时间后刷新设备列表
            // 这样可以避免设备刚连接时 cfgutil 还未识别到设备
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refreshDeviceList()
            }
        }
    }
    
    // MARK: - 设备列表
    
    /// 设置设备列表表格视图
    private func setupDeviceTableView() {
        guard let tableView = deviceTableView else { return }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClick(_:))
        
        // 设置表头标题
        if tableView.tableColumns.count >= 3 {
            tableView.tableColumns[0].headerCell.stringValue = L("Device_Status_DFU")
            tableView.tableColumns[1].headerCell.stringValue = L("Device_Chip_Type")
            tableView.tableColumns[2].headerCell.stringValue = L("Device_List_Header")
        }
    }
    
    /// 刷新设备列表并显示在设备列表表格视图中
    private func refreshDeviceList() {
        log(false, L("Device_List_Refresh_Start"))
        
        guard let cfgutilPath = checkCfgutil(), checkConfigurationFrameworks() else {
            // 使用预设设备
            log(L("Device_Cfgutil_Not_Found"))
            DispatchQueue.main.async {
                self.devices = Device.presetDevices
                self.deviceTableView?.reloadData()
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let cfgutilDir = (cfgutilPath as NSString).deletingLastPathComponent
                let result = try self.doCfgutilTask(cfgutilPath, with: ["list"], cwd: cfgutilDir)
                
                let devices: [Device] = {
                    guard let output = String(data: result.data, encoding: .utf8) else {
                        return Device.presetDevices
                    }
                    let parsed = DeviceManager.parse(output)
                    return parsed.isEmpty ? Device.presetDevices : parsed
                }()
                
                log(false, L("Device_Detected_Count", devices.count))
                
                // 使用多线程并行检查每个设备的 DFU 状态
                let group = DispatchGroup()
                let queue = DispatchQueue(label: "com.dfu.deviceStatusCheck", attributes: .concurrent)
                let lock = NSLock()
                var updatedDevices = devices  // 创建副本用于多线程修改
                
                for i in 0..<devices.count {
                    group.enter()
                    queue.async {
                        let isInDFU = DeviceManager.checkDFUStatus(devices[i], cfgutilPath: cfgutilPath)
                        lock.lock()
                        var device = devices[i]
                        device.isInDFU = isInDFU
                        updatedDevices[i] = device
                        lock.unlock()
                        let statusText = isInDFU ? L("Device_Status_Yes") : L("Device_Status_No")
                        log(false, L("Device_Status_Info", device.type, device.ecid, statusText))
                        group.leave()
                    }
                }
                
                // 等待所有设备状态检查完成
                group.wait()
                
                // 在主线程更新设备列表
                let finalDevices = updatedDevices
                DispatchQueue.main.async {
                    self.devices = finalDevices
                    self.deviceTableView?.reloadData()
                    log(false, L("Device_List_Update_Success", finalDevices.count))
                }
            } catch {
                log(L("Device_List_Refresh_Failed", error.localizedDescription))
                DispatchQueue.main.async {
                    self.devices = Device.presetDevices
                    self.deviceTableView?.reloadData()
                    log(L("Device_List_Refresh_Failed", error.localizedDescription))
                }
            }
        }
    }
    
    /// 表格视图双击事件
    @objc private func tableViewDoubleClick(_ sender: Any) {
        // 可以在这里添加双击设备时的操作
    }
    
    // MARK: - IPSW 相关方法
    
    /// 设置 ipswPathLabel 的点击手势
    private func setupIPSWPathLabelClick() {
        // 创建点击手势识别器
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(ipswPathLabelClicked(_:)))
        ipswPathLabel?.addGestureRecognizer(clickGesture)
        
        // 设置标签为不可选择和不可编辑
        ipswPathLabel?.isSelectable = false
        ipswPathLabel?.isEditable = false
    }
    
    /// 设置 ipswPathLabel 的文本，带文件夹图标
    private func updateIPSWPathLabelText(_ fileName: String, color: NSColor = .labelColor) {
        guard let label = ipswPathLabel else { return }
        
        let attributedString = NSMutableAttributedString()
        
        // 添加文件夹图标
        if #available(macOS 10.15, *) {
            if let folderImage = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) {
                // 调整图标大小以匹配文本
                let fontSize = label.font?.pointSize ?? 13
                folderImage.size = NSSize(width: fontSize, height: fontSize)
                
                // 创建图片附件
                let imageAttachment = NSTextAttachment()
                imageAttachment.image = folderImage
                imageAttachment.bounds = CGRect(x: 0, y: -2, width: fontSize, height: fontSize)
                
                let imageString = NSAttributedString(attachment: imageAttachment)
                attributedString.append(imageString)
                
                // 添加空格
                attributedString.append(NSAttributedString(string: " "))
            }
        }
        
        // 添加文件名
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: label.font ?? NSFont.systemFont(ofSize: 13)
        ]
        let fileNameString = NSAttributedString(string: fileName, attributes: textAttributes)
        attributedString.append(fileNameString)
        
        label.attributedStringValue = attributedString
    }
    
    /// 处理 ipswPathLabel 点击事件
    @objc private func ipswPathLabelClicked(_ sender: NSClickGestureRecognizer) {
        openIPSWFolder()
    }
    
    /// 打开 IPSW 文件所在目录
    private func openIPSWFolder() {
        // 检查是否有选中的 IPSW 文件
        guard let ipswPath = selectedIPSWPath,
              !ipswPath.isEmpty,
              FileManager.default.fileExists(atPath: ipswPath) else {
            return
        }
        
        // 打开文件所在目录并选中文件
        let fileURL = URL(fileURLWithPath: ipswPath)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
    
    /// 从配置文件加载 IPSW 路径
    private func loadIPSWFromConfig() {
        if let ipswPath = PasswordManager.shared.ipswPath(),
           !ipswPath.isEmpty,
           FileManager.default.fileExists(atPath: ipswPath) {
            selectedIPSWPath = ipswPath
            updateIPSWPathLabelText(URL(fileURLWithPath: ipswPath).lastPathComponent, color: .labelColor)
            // 如果配置文件中有 IPSW，自动勾选使用 IPSW 复选框
            useIPSWCheckbox?.state = .on
        }
    }
    
    @IBAction func useIPSWChanged(_ sender: Any) {
        updateIPSWControls()
    }
    
    @IBAction func selectIPSWFile(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = ["ipsw"] // 允许 IPSW 文件类型
        openPanel.allowsOtherFileTypes = true // 也允许其他文件类型
        openPanel.message = L("IPSW_Select_File")
        openPanel.prompt = L("Button_Select")
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                selectedIPSWPath = url.path
                updateIPSWPathLabelText(url.lastPathComponent, color: .labelColor)
                
                // 保存到 JSON 配置文件
                PasswordManager.shared.updateIPSW(url.path)
            }
        }
    }
    
    private func updateIPSWControls() {
        let isEnabled = useIPSWCheckbox?.state == .on
        selectIPSWButton?.isEnabled = isEnabled
        ipswPathLabel?.isEnabled = isEnabled
        
        if isEnabled {
            // 如果启用，尝试从配置文件恢复 IPSW 路径
            if selectedIPSWPath == nil {
                if let ipswPath = PasswordManager.shared.ipswPath(),
                   !ipswPath.isEmpty,
                   FileManager.default.fileExists(atPath: ipswPath) {
                    selectedIPSWPath = ipswPath
                    updateIPSWPathLabelText(URL(fileURLWithPath: ipswPath).lastPathComponent, color: .labelColor)
                } else {
                    ipswPathLabel?.stringValue = L("IPSW_No_File_Selected")
                    ipswPathLabel?.textColor = .secondaryLabelColor
                }
            }
        } else {
            selectedIPSWPath = nil
            ipswPathLabel?.stringValue = L("IPSW_No_File_Selected")
            ipswPathLabel?.textColor = .secondaryLabelColor
        }
    }
    
    // MARK: - 链接跳转
    
    @IBAction func openIPSWLink(_ sender: Any) {
        // 打开 IPSW 相关链接
        if let url = URL(string: "https://ipsw.me/product/Mac") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @IBAction func openMDMLink(_ sender: Any) {
        // 打开 MDM 相关链接
        if let url = URL(string: "http://mdm.xrsec.fun") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @IBAction func clearLogs(_ sender: Any) {
        LogManager.shared.clear()
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func enterDfu(_ sender: Any) {
        guard DeviceBindingManager.shared.isAuthorized else {
            log(false, L("Auth_Buttons_Disabled"))
            return
        }

        executeSecureCommand(
            .dfu,
            needle: "rebooting target into dfu mode... ok",
            successTitle: L("Operation_DFU_Success"),
            successMessage: L("Operation_DFU_Success_Message"),
            error: L("Operation_DFU_Error")
        )
    }
    
    @IBAction func reboot(_ sender: Any) {
        guard DeviceBindingManager.shared.isAuthorized else {
            log(false, L("Auth_Buttons_Disabled"))
            return
        }

        executeSecureCommand(
            .reboot,
            needle: "rebooting target into normal mode... ok",
            successTitle: L("Operation_Reboot_Success"),
            successMessage: L("Operation_Reboot_Success_Message"),
            error: L("Operation_Reboot_Error")
        )
    }
    
    @IBAction func restore(_ sender: Any) {
        // 检查是否有设备
        guard !devices.isEmpty else {
            AlertManager.shared.showAlert(
                title: L("Device_List_Empty"),
                message: L("Device_List_Connect_First"),
                alertStyle: .warning
            )
            return
        }
        
        // 禁用按钮
        self.restoreButton.isEnabled = false
        self.reviveButton.isEnabled = false
        self.dfuButton.isEnabled = false
        self.rebootButton.isEnabled = false
        
        // 遍历所有设备，使用多线程处理
        restoreDevices(devices: devices, isRestore: true)
    }
    
    @IBAction func revive(_ sender: Any) {
        // 检查是否有设备
        guard !devices.isEmpty else {
            AlertManager.shared.showAlert(
                title: L("Device_List_Empty"),
                message: L("Device_List_Connect_First"),
                alertStyle: .warning
            )
            return
        }
        
        // 禁用按钮
        self.restoreButton.isEnabled = false
        self.reviveButton.isEnabled = false
        self.dfuButton.isEnabled = false
        self.rebootButton.isEnabled = false
        
        // 遍历所有设备，使用多线程处理
        restoreDevices(devices: devices, isRestore: false)
    }
    
    @objc private func handleAuthorizationStatusChanged() {
        updateSecureButtonStates()
    }

    private func updateSecureButtonStates() {
        let isAuthorized = DeviceBindingManager.shared.isAuthorized
        dfuButton?.isEnabled = isAuthorized
        rebootButton?.isEnabled = isAuthorized

        if !isAuthorized {
            log(false, L("Auth_Buttons_Disabled"))
        }
    }

    private func executeSecureCommand(_ command: SecureDFUCommand, needle: String, successTitle: String, successMessage: String, error: String) {
        // 不清空日志，追加分隔符
        let separator = "\n\n"
        DispatchQueue.main.async {
            let currentText = self.outputTextView.string
            self.outputTextView.string = currentText + separator
            self.outputTextView.scrollToEndOfDocument(nil)
        }
        
        self.dfuButton.isEnabled = false
        self.rebootButton.isEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try SecureDFUManager.shared.executeCommand(command)
                let output = result.output
                
                DispatchQueue.main.async {
                    // 追加命令输出到日志，而不是替换
                    if !output.isEmpty {
                        let currentText = self.outputTextView.string
                        self.outputTextView.string = currentText + output
                        self.outputTextView.scrollToEndOfDocument(nil)
                        log(false, output)
                    }

                    if result.status == 0 && output.lowercased().contains(needle.lowercased()) {
                        log("✅ \(successTitle)")
                        AlertManager.shared.showAlert(
                            title: successTitle,
                            message: successMessage,
                            alertStyle: .informational
                        )
                    } else {
                        log("❌ \(error)")
                        AlertManager.shared.showAlert(
                            title: error,
                            message: self.secureCommandFailureMessage(
                                for: command,
                                output: output,
                                defaultError: error,
                                exitCode: result.status
                            ),
                            alertStyle: .warning
                        )
                    }
                    self.dfuButton.isEnabled = true
                    self.rebootButton.isEnabled = true
                }
            } catch {
                DispatchQueue.main.async {
                    log("❌ Error: \(error.localizedDescription)")
                    AlertManager.shared.showAlert(
                        title: L("Error_Title"),
                        message: error.localizedDescription,
                        alertStyle: .warning
                    )
                    self.dfuButton.isEnabled = true
                    self.rebootButton.isEnabled = true
                }
            }
        }
    }

    private var dfuErrorHints: [String] {
        [
            L("Operation_DFU_Error_Hint_1"),
            L("Operation_DFU_Error_Hint_2"),
            L("Operation_DFU_Error_Hint_3"),
            L("Operation_DFU_Error_Hint_4"),
        ]
    }

    private func handleDFUError() -> String {
        let hints = dfuErrorHints
        hints.forEach { log(false, $0) }
        return hints.joined(separator: "\n")
    }

    private func secureCommandFailureMessage(for command: SecureDFUCommand, output: String, defaultError: String, exitCode: Int32) -> String {
        let lowerOutput = output.lowercased()
        let isPermissionError = lowerOutput.contains("iocreateplugininterfaceforservice failed")
        let isNoConnection = lowerOutput.contains("connection: none") && lowerOutput.contains("no connection detected")
        let isVDMFailed = lowerOutput.contains("connection: sink") && lowerOutput.contains("vdm failed")

        if command == .dfu || command == .reboot {
            if isPermissionError {
                log(L("Operation_DFU_Permission_Error"))
                return [
                    L("Operation_DFU_Permission_Error"),
                    L("Operation_DFU_Permission_Error_Hint"),
                ].joined(separator: "\n")
            }

            if isNoConnection {
                log(L("Operation_DFU_No_Connection"))
                return [
                    L("Operation_DFU_No_Connection"),
                    L("Operation_DFU_No_Connection_Hint"),
                ].joined(separator: "\n")
            }

            if isVDMFailed {
                log(L("Operation_DFU_VDM_Failed"))
                return [
                    L("Operation_DFU_VDM_Failed"),
                    L("Operation_DFU_VDM_Failed_Hint"),
                ].joined(separator: "\n")
            }

            return handleDFUError()
        }

        return [
            defaultError,
            L("Error_Exit_Code", exitCode),
        ].joined(separator: "\n")
    }
    
    // MARK: - cfgutil 相关方法
    
    /// 检查 cfgutil 工具是否可用
    private func checkCfgutil() -> String? {
        let cfgutilPath = "/Applications/Apple Configurator.app/Contents/MacOS/cfgutil"
        if FileManager.default.fileExists(atPath: cfgutilPath) {
            return cfgutilPath
        }
        return nil
    }
    
    /// 检查 ConfigurationProfile 框架是否可用
    private func checkConfigurationFrameworks() -> Bool {
        let frameworksPath = "/Applications/Apple Configurator.app/Contents/Frameworks"
        let requiredFrameworks = [
            "ConfigurationProfile.framework",
            "ConfigurationProfileUI.framework",
            "ConfigurationUtilityKit.framework"
        ]
        
        for framework in requiredFrameworks {
            let frameworkPath = "\(frameworksPath)/\(framework)"
            if !FileManager.default.fileExists(atPath: frameworkPath) {
                return false
            }
        }
        return true
    }
    
    /// 显示 Apple Configurator 缺失提示
    private func showAppleConfiguratorMissingAlert() {
        DispatchQueue.main.async {
            AlertManager.shared.showAlert(
                title: L("Configurator_Required"),
                message: L("Configurator_Not_Found"),
                alertStyle: .critical
            )
        }
    }
    
    /// 显示框架缺失提示
    private func showFrameworkMissingAlert() {
        DispatchQueue.main.async {
            AlertManager.shared.showAlert(
                title: L("Configurator_Framework_Missing"),
                message: L("Configurator_Framework_Not_Found"),
                alertStyle: .critical
            )
        }
    }
    
    /// 遍历所有设备并执行 restore 或 revive 操作（使用多线程）
    private func restoreDevices(devices: [Device], isRestore: Bool) {
        // 检查 cfgutil 工具是否可用
        guard let cfgutilPath = checkCfgutil() else {
            DispatchQueue.main.async {
                self.showAppleConfiguratorMissingAlert()
                self.restoreButton.isEnabled = true
                self.reviveButton.isEnabled = true
                self.dfuButton.isEnabled = true
                self.rebootButton.isEnabled = true
            }
            return
        }
        
        // 检查框架是否可用
        guard checkConfigurationFrameworks() else {
            DispatchQueue.main.async {
                self.showFrameworkMissingAlert()
                self.restoreButton.isEnabled = true
                self.reviveButton.isEnabled = true
                self.dfuButton.isEnabled = true
                self.rebootButton.isEnabled = true
            }
            return
        }
        
        // 不清空日志，追加分隔符
        let separator = "\n\n"
        DispatchQueue.main.async {
            let currentText = self.outputTextView.string
            self.outputTextView.string = currentText + separator
            self.outputTextView.scrollToEndOfDocument(nil)
        }
        
        let operationName = isRestore ? "restore" : "revive"
        log(false, L("Operation_Start_Multiple", operationName, devices.count))
        
        DispatchQueue.global(qos: .userInitiated).async {
            let cfgutilDir = (cfgutilPath as NSString).deletingLastPathComponent
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "com.dfu.restoreQueue", attributes: .concurrent)
            let lock = NSLock()
            var successCount = 0
            var failCount = 0
            
            // 为每个设备创建恢复任务
            for device in devices {
                group.enter()
                queue.async {
                    // 构建命令参数（不指定 -e，cfgutil 自动处理所有设备）
                    var args = [operationName, "--progress", "-v"]
                    
                    // 如果选择了 IPSW 文件，使用 -I 参数
                    if self.useIPSWCheckbox?.state == .on, let ipswPath = self.selectedIPSWPath {
                        args.append("-I")
                        args.append(ipswPath)
                    }
                    
                    log(false, L("Operation_Start_Single", operationName, device.type, device.ecid))
                    
                    do {
                        let result = try self.doCfgutilTask(cfgutilPath, with: args, cwd: cfgutilDir)
                        
                        guard let output = String(data: result.data, encoding: .utf8) else {
                            lock.lock()
                            failCount += 1
                            lock.unlock()
                            log(L("Operation_Device_Failed_Output", device.type, device.ecid, operationName))
                            group.leave()
                            return
                        }
                        
                        // 检查是否成功
                        let lowerOutput = output.lowercased()
                        let hasError = lowerOutput.contains("error") ||
                                      lowerOutput.contains("failed") ||
                                      lowerOutput.contains("no devices found") ||
                                      lowerOutput.contains("could not") ||
                                      lowerOutput.contains("unable to") ||
                                      lowerOutput.contains("cannot")
                        
                        let hasSuccess = lowerOutput.contains("success") ||
                                        lowerOutput.contains("completed") ||
                                        lowerOutput.contains("finished") ||
                                        (result.status == 0 && !hasError)
                        
                        lock.lock()
                        if result.status == 0 && hasSuccess && !hasError {
                            successCount += 1
                            log(false, L("Operation_Device_Success", device.type, device.ecid, operationName))
                        } else {
                            failCount += 1
                            log(L("Operation_Device_Failed_Exit", device.type, device.ecid, operationName, result.status))
                        }
                        lock.unlock()
                        
                    } catch {
                        lock.lock()
                        failCount += 1
                        lock.unlock()
                        log(L("Operation_Device_Failed_Error", device.type, device.ecid, operationName, error.localizedDescription))
                    }
                    
                    group.leave()
                }
            }
            
            // 等待所有任务完成
            group.wait()
            
            // 显示最终结果
            DispatchQueue.main.async {
                let totalCount = devices.count

                let title: String
                let message: String
                let style: NSAlert.Style

                if failCount == 0 {
                    title = L("Operation_Success")
                    style = .informational
                    if isRestore {
                        message = L("Operation_Restore_Success_All", totalCount)
                    } else {
                        message = L("Operation_Revive_Success_All", totalCount)
                    }
                } else if successCount > 0 {
                    title = L("Operation_Partial_Success")
                    message = L("Operation_Success_Count", successCount, failCount)
                    style = .warning
                } else {
                    title = L("Operation_Failed")
                    style = .critical
                    if isRestore {
                        message = L("Operation_Restore_Failed_All", totalCount)
                    } else {
                        message = L("Operation_Revive_Failed_All", totalCount)
                    }
                }

                AlertManager.shared.showAlert(title: title, message: message, alertStyle: style)
                self.restoreButton.isEnabled = true
                self.reviveButton.isEnabled = true
                self.dfuButton.isEnabled = true
                self.rebootButton.isEnabled = true
            }
        }
    }
    
    private func doCfgutilCmd(_ args: [String], needle: String, success: String, error: String) {
        
        // 检查 cfgutil 工具是否可用
        guard let cfgutilPath = checkCfgutil() else {
            showAppleConfiguratorMissingAlert()
            return
        }
        
        // 检查框架是否可用
        guard checkConfigurationFrameworks() else {
            showFrameworkMissingAlert()
            return
        }
        
        // 不清空日志，追加分隔符
        let separator = "\n\n"
        DispatchQueue.main.async {
            let currentText = self.outputTextView.string
            self.outputTextView.string = currentText + separator
            self.outputTextView.scrollToEndOfDocument(nil)
        }
        
        self.dfuButton.isEnabled = false
        self.rebootButton.isEnabled = false
        self.restoreButton.isEnabled = false
        self.reviveButton.isEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            var result: STReturn = (status: 0, error: 0, data: Data())
            do {
                
                // cfgutil 不需要 sudo，直接执行
                let cfgutilDir = (cfgutilPath as NSString).deletingLastPathComponent
                result = try self.doCfgutilTask(cfgutilPath, with: args, cwd: cfgutilDir)
                
                guard let output = String(data: result.data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        self.dfuButton.isEnabled = true
                        self.rebootButton.isEnabled = true
                        self.restoreButton.isEnabled = true
                        self.reviveButton.isEnabled = true
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    // 输出已经在实时更新中显示，这里只需要显示最终结果
                    // cfgutil 成功时返回 0，失败时返回非 0
                    // 检查输出中是否包含错误信息
                    let lowerOutput = output.lowercased()
                    let hasError = lowerOutput.contains("error") || 
                                  lowerOutput.contains("failed") ||
                                  lowerOutput.contains("no devices found") ||
                                  lowerOutput.contains("could not") ||
                                  lowerOutput.contains("unable to") ||
                                  lowerOutput.contains("cannot")
                    
                    // 检查是否包含成功信息
                    let hasSuccess = lowerOutput.contains("success") ||
                                    lowerOutput.contains("completed") ||
                                    lowerOutput.contains("finished") ||
                                    (result.status == 0 && !hasError)

                    if result.status == 0 && hasSuccess && !hasError {
                        AlertManager.shared.showAlert(
                            title: L("Operation_Success"),
                            message: success,
                            alertStyle: .informational
                        )
                    } else {
                        var errorMsg = "\(error)\n\(L("Error_Exit_Code", result.status))"

                        // 提取关键错误信息
                        let lines = output.components(separatedBy: .newlines)
                        let errorLines = lines.filter { line in
                            let lowerLine = line.lowercased()
                            return lowerLine.contains("error") || 
                                   lowerLine.contains("failed") ||
                                   lowerLine.contains("cannot") ||
                                   lowerLine.contains("unable")
                        }
                        
                        if !errorLines.isEmpty {
                            errorMsg += "\n\n\(L("Error_Info"))" + errorLines.prefix(5).joined(separator: "\n")
                        }

                        AlertManager.shared.showAlert(
                            title: L("Operation_Failed"),
                            message: errorMsg,
                            alertStyle: .warning
                        )
                    }
                    self.dfuButton.isEnabled = true
                    self.rebootButton.isEnabled = true
                    self.restoreButton.isEnabled = true
                    self.reviveButton.isEnabled = true
                }
                
            } catch STError.authCancelled {
                
                DispatchQueue.main.async {
                    self.dfuButton.isEnabled = true
                    self.rebootButton.isEnabled = true
                    self.restoreButton.isEnabled = true
                    self.reviveButton.isEnabled = true
                }
                return
                
            } catch {
                DispatchQueue.main.async {
                    AlertManager.shared.showAlert(
                        title: L("Error_Title"),
                        message: L("Error_Command_Execution", error.localizedDescription),
                        alertStyle: .critical
                    )
                    self.dfuButton.isEnabled = true
                    self.rebootButton.isEnabled = true
                    self.restoreButton.isEnabled = true
                    self.reviveButton.isEnabled = true
                }
                return
            }
        }
    }
    
    private func doCfgutilTask(_ path: String, with arguments: [String], cwd: String) throws -> STReturn {
        
        // cfgutil 通常不需要 sudo，直接执行
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryPath = cwd
        
        // 设置环境变量，确保 cfgutil 能找到框架
        // 使用系统的 Apple Configurator.app 的 Frameworks 目录
        var environment = ProcessInfo.processInfo.environment
        let systemFrameworksPath = "/Applications/Apple Configurator.app/Contents/Frameworks"
        
        // 检查系统框架路径是否存在
        if FileManager.default.fileExists(atPath: systemFrameworksPath) {
            // 设置 DYLD_FRAMEWORK_PATH 指向系统的 Frameworks 目录
            if let existingPath = environment["DYLD_FRAMEWORK_PATH"] {
                environment["DYLD_FRAMEWORK_PATH"] = "\(existingPath):\(systemFrameworksPath)"
            } else {
                environment["DYLD_FRAMEWORK_PATH"] = systemFrameworksPath
            }
        }
        process.environment = environment
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // 用于收集输出数据
        var outputData = Data()
        var errorData = Data()
        
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        // 使用类来包装缓冲区，以便在闭包中正确共享
        class Buffer {
            var content: String = ""
        }
        let outputBuffer = Buffer()
        let errorBuffer = Buffer()
        
        // 存储观察者以便后续移除
        var outputObserver: NSObjectProtocol?
        var errorObserver: NSObjectProtocol?
        
        // 设置输出读取通知
        outputHandle.readInBackgroundAndNotify()
        outputObserver = NotificationCenter.default.addObserver(
            forName: FileHandle.readCompletionNotification,
            object: outputHandle,
            queue: nil
        ) { notification in
            if let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? Data,
               !data.isEmpty {
                outputData.append(data)
                
                if let text = String(data: data, encoding: .utf8) {
                    outputBuffer.content += text
                    
                    // 按行更新 UI
                    let lines = outputBuffer.content.components(separatedBy: .newlines)
                    if lines.count > 1 {
                        let completeLines = lines.dropLast()
                        DispatchQueue.main.async {
                            let currentText = self.outputTextView.string
                            self.outputTextView.string = currentText + completeLines.joined(separator: "\n") + "\n"
                            self.outputTextView.scrollToEndOfDocument(nil)
                        }
                        outputBuffer.content = lines.last ?? ""
                    }
                }
                
                // 继续读取
                outputHandle.readInBackgroundAndNotify()
            }
        }
        
        // 设置错误读取通知
        errorHandle.readInBackgroundAndNotify()
        errorObserver = NotificationCenter.default.addObserver(
            forName: FileHandle.readCompletionNotification,
            object: errorHandle,
            queue: nil
        ) { notification in
            if let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? Data,
               !data.isEmpty {
                errorData.append(data)
                
                if let text = String(data: data, encoding: .utf8) {
                    errorBuffer.content += text
                    
                    // 按行更新 UI
                    let lines = errorBuffer.content.components(separatedBy: .newlines)
                    if lines.count > 1 {
                        let completeLines = lines.dropLast()
                        DispatchQueue.main.async {
                            let currentText = self.outputTextView.string
                            self.outputTextView.string = currentText + completeLines.joined(separator: "\n") + "\n"
                            self.outputTextView.scrollToEndOfDocument(nil)
                        }
                        errorBuffer.content = lines.last ?? ""
                    }
                }
                
                // 继续读取
                errorHandle.readInBackgroundAndNotify()
            }
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // 读取剩余数据
            let remainingOutput = outputHandle.readDataToEndOfFile()
            let remainingError = errorHandle.readDataToEndOfFile()
            
            if !remainingOutput.isEmpty {
                outputData.append(remainingOutput)
                if let output = String(data: remainingOutput, encoding: .utf8) {
                    DispatchQueue.main.async {
                        let currentText = self.outputTextView.string
                        self.outputTextView.string = currentText + output
                        self.outputTextView.scrollToEndOfDocument(nil)
                    }
                }
            }
            
            if !remainingError.isEmpty {
                errorData.append(remainingError)
                if let output = String(data: remainingError, encoding: .utf8) {
                    DispatchQueue.main.async {
                        let currentText = self.outputTextView.string
                        self.outputTextView.string = currentText + output
                        self.outputTextView.scrollToEndOfDocument(nil)
                    }
                }
            }
            
            // 处理剩余的缓冲区内容
            if !outputBuffer.content.isEmpty {
                DispatchQueue.main.async {
                    let currentText = self.outputTextView.string
                    self.outputTextView.string = currentText + outputBuffer.content
                    self.outputTextView.scrollToEndOfDocument(nil)
                }
            }
            
            if !errorBuffer.content.isEmpty {
                DispatchQueue.main.async {
                    let currentText = self.outputTextView.string
                    self.outputTextView.string = currentText + errorBuffer.content
                    self.outputTextView.scrollToEndOfDocument(nil)
                }
            }
            
            // 移除观察者
            if let observer = outputObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = errorObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            
            // 合并输出和错误
            var combinedData = outputData
            if !errorData.isEmpty {
                combinedData.append(errorData)
            }
            
            return (process.terminationStatus, 0, combinedData)
        } catch {
            // 移除观察者
            if let observer = outputObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = errorObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            throw error
        }
    }
    
}

// MARK: - NSTableViewDataSource
extension ViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return devices.count
    }
}

// MARK: - NSTableViewDelegate
extension ViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < devices.count else { return nil }
        let device = devices[row]
        
        // 根据列标识符返回不同的视图
        guard let identifier = tableColumn?.identifier else { return nil }
        
        if identifier.rawValue == "DeviceColumn" {
            // 设备信息列 - 使用标准的 NSTableCellView
            let cellIdentifier = NSUserInterfaceItemIdentifier("DeviceCell")
            var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            
            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = cellIdentifier
                let textField = NSTextField()
                textField.isEditable = false
                textField.isBordered = false
                textField.backgroundColor = .clear
                textField.font = NSFont.systemFont(ofSize: 11)
                cell?.textField = textField
                cell?.addSubview(textField)
                textField.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                ])
            }
            
            cell?.textField?.stringValue = device.type
            return cell
        } else if identifier.rawValue == "StatusColumn" {
            // 状态列（勾选框）- 使用自定义视图包含 checkbox
            let cellIdentifier = NSUserInterfaceItemIdentifier("StatusCell")
            var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self)
            
            if cell == nil {
                // 创建一个容器视图
                let containerView = NSView()
                containerView.identifier = cellIdentifier
                
                // 创建 checkbox
                let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                checkbox.isEnabled = false  // 只读，不能手动修改
                checkbox.state = .off
                checkbox.translatesAutoresizingMaskIntoConstraints = false
                containerView.addSubview(checkbox)
                
                NSLayoutConstraint.activate([
                    checkbox.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                    checkbox.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
                ])
                
                cell = containerView
            }
            
            // 更新 checkbox 状态
            if let containerView = cell,
               let checkbox = containerView.subviews.first as? NSButton {
                checkbox.state = device.isInDFU ? .on : .off
            }
            
            return cell
        } else if identifier.rawValue == "ChipColumn" {
            // 芯片类型列 - 显示 M/A/T2/Intel
            let cellIdentifier = NSUserInterfaceItemIdentifier("ChipCell")
            var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            
            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = cellIdentifier
                let textField = NSTextField()
                textField.isEditable = false
                textField.isBordered = false
                textField.backgroundColor = .clear
                textField.font = NSFont.systemFont(ofSize: 11)
                textField.alignment = .center
                cell?.textField = textField
                cell?.addSubview(textField)
                textField.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 2),
                    textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                ])
            }
            
            // 根据芯片类型显示本地化字符串
            let chipDisplay: String
            switch device.chipType {
            case "M": chipDisplay = L("Device_Chip_M")
            case "A": chipDisplay = L("Device_Chip_A")
            case "T": chipDisplay = L("Device_Chip_T")
            default: chipDisplay = L("Device_Chip_O")
            }
            cell?.textField?.stringValue = chipDisplay
            return cell
        }
        
        return nil
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 22.0
    }
}
