//
//  AppDelegate.swift
//  DFU-Tools
//
//  Created by Wayne Bonnici on 27/04/2022.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    override init() {
        super.init()
        _ = LanguageManager.shared
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        PasswordManager.shared.clearCachedPassword()
        updateMenuTitles()
        updateLanguageMenuState()
        checkDeviceBinding()
    }

    // MARK: - Menu Localization

    private func updateMenuTitles() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }

        func updateMenuRecursively(_ menu: NSMenu) {
            for item in menu.items {
                if let identifier = item.identifier?.rawValue {
                    switch identifier {
                    case "1Xt-HY-uBw", "uQy-DD-JDr":
                        item.title = L("Menu_App_Name")
                    case "5kV-Vb-QxS":
                        item.title = L("Menu_About")
                    case "Olw-nP-bQN":
                        item.title = L("Menu_Hide_App")
                    case "Vdr-fp-XzO":
                        item.title = L("Menu_Hide_Others")
                    case "Kd2-mp-pUS":
                        item.title = L("Menu_Show_All")
                    case "4sb-4s-VLi":
                        item.title = L("Menu_Quit")
                    case "Lang-Menu-Item":
                        item.title = L("Menu_Language")
                    case "Lang-Auto":
                        item.title = L("Menu_Auto")
                    case "Lang-EN":
                        item.title = L("Menu_English")
                    case "Lang-ZH":
                        item.title = L("Menu_Simplified_Chinese")
                    default:
                        break
                    }
                }

                if let submenu = item.submenu {
                    if let identifier = submenu.identifier?.rawValue {
                        switch identifier {
                        case "uQy-DD-JDr", "Lang-Submenu":
                            submenu.title = item.title
                        default:
                            break
                        }
                    }
                    updateMenuRecursively(submenu)
                }
            }
        }

        updateMenuRecursively(mainMenu)
    }
    
    // MARK: - About 面板
    
    @IBAction func showAbout(_ sender: Any?) {
        let aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        aboutWindow.title = L("About_Title")
        aboutWindow.center()
        aboutWindow.isReleasedWhenClosed = false
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 580, height: 480))
        textView.isEditable = false
        textView.isSelectable = true
        textView.string = """
        \(L("About_App_Name"))
        
        \(L("About_Subtitle"))
        
        \(L("About_Version"))
        \(L("About_Copyright"))
        
        \(L("About_DFU_Port_Title"))
        \(L("About_DFU_Port_M4"))
        \(L("About_DFU_Port_M1_M2_M3"))
        \(L("About_DFU_Port_Intel_T2"))
        \(L("About_DFU_Port_Note"))
        
        \(L("About_Guide_Title"))
        
        \(L("About_Guide_1_Title"))
        \(L("About_Guide_1_1"))
        \(L("About_Guide_1_2"))
        
        \(L("About_Guide_2_Title"))
        \(L("About_Guide_2_1"))
        \(L("About_Guide_2_2"))
        
        \(L("About_Guide_3_Title"))
        \(L("About_Guide_3_1"))
        \(L("About_Guide_3_2"))
        \(L("About_Guide_3_3"))
        
        \(L("About_Guide_4_Title"))
        \(L("About_Guide_4_1"))
        \(L("About_Guide_4_2"))
        
        \(L("About_Guide_5_Title"))
        \(L("About_Guide_5_1"))
        \(L("About_Guide_5_2"))
        
        \(L("About_Guide_6_Title"))
        \(L("About_Guide_6_1"))
        \(L("About_Guide_6_2"))
        \(L("About_Guide_6_3"))
        
        \(L("About_Notes_Title"))
        \(L("About_Notes_1"))
        \(L("About_Notes_2"))
        \(L("About_Notes_3"))
        \(L("About_Notes_4"))
        
        \(L("About_Support_Title"))
        \(L("About_Support_1"))
        \(L("About_Support_2"))
        """
        
        scrollView.documentView = textView
        aboutWindow.contentView = scrollView
        
        aboutWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - 语言切换
    
    @IBAction func switchToAuto(_ sender: Any) {
        LanguageManager.shared.switchLanguage(LanguageManager.autoLanguageCode)
    }
    
    @IBAction func switchToEnglish(_ sender: Any) {
        LanguageManager.shared.switchLanguage("en")
    }
    
    @IBAction func switchToChinese(_ sender: Any) {
        LanguageManager.shared.switchLanguage("zh-Hans")
    }

    private func checkDeviceBinding() {
        log(false, L("Auth_Checking"))
        logDeviceInfo()

        DeviceBindingManager.shared.verifyAuthorization { _, message in
            if let message, !message.isEmpty {
                log(false, message)
            }
            NotificationCenter.default.post(name: .authorizationStatusChanged, object: nil)
        }
    }

    private func logDeviceInfo() {
        let deviceInfo = DeviceBindingManager.shared.deviceInfo()
        guard !deviceInfo.isEmpty else {
            log(false, L("Auth_Device_Info_Failed"))
            return
        }

        log(false, L("Auth_Device_Info"))
        for (key, value) in deviceInfo.sorted(by: { $0.key < $1.key }) {
            log(false, "  \(key): \(value)")
        }
    }

    private func updateLanguageMenuState() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        
        func findMenuItem(_ menu: NSMenu, action: Selector) -> NSMenuItem? {
            for item in menu.items {
                if item.action == action { return item }
                if let submenu = item.submenu, let found = findMenuItem(submenu, action: action) {
                    return found
                }
            }
            return nil
        }
        
        let saved = UserDefaults.standard.string(forKey: "DFU-Tools-Language") ?? LanguageManager.autoLanguageCode
        
        findMenuItem(mainMenu, action: #selector(switchToAuto(_:)))?.state = saved == LanguageManager.autoLanguageCode ? .on : .off
        findMenuItem(mainMenu, action: #selector(switchToEnglish(_:)))?.state = saved == "en" ? .on : .off
        findMenuItem(mainMenu, action: #selector(switchToChinese(_:)))?.state = saved == "zh-Hans" ? .on : .off
    }
}
