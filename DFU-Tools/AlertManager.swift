//
//  AlertManager.swift
//  DFU-Tools
//
//  统一提示弹窗与密码输入弹窗，交互风格尽量与 micaixin 保持接近。
//

import Cocoa

private enum AlertLayoutConstants {
    static let alertWidth: CGFloat = 330
    static let padding: CGFloat = 16
    static let buttonHeight: CGFloat = 28
    static let buttonBottomMargin: CGFloat = 12
    static let buttonWidth: CGFloat = 80
    static let messageSpacing: CGFloat = 6
    static let inputHeight: CGFloat = 24
    static let inputTopMargin: CGFloat = 12
    static let minAlertHeight: CGFloat = 60
    static let minPasswordDialogHeight: CGFloat = 120

    static let messageFontSize: CGFloat = 13
    static let informativeFontSize: CGFloat = 12

    static var messageFont: NSFont {
        NSFont.boldSystemFont(ofSize: messageFontSize)
    }

    static var informativeFont: NSFont {
        NSFont.systemFont(ofSize: informativeFontSize)
    }

    static func calculateCenterPosition(width: CGFloat, height: CGFloat, in parentFrame: NSRect) -> NSPoint {
        NSPoint(
            x: parentFrame.midX - width / 2,
            y: parentFrame.midY - height / 2
        )
    }

    static func calculateTextHeight(text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = attributedString.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(textRect.height)
    }
}

class AlertManager {
    static let shared = AlertManager()

    private let autoDismissDuration: TimeInterval = 5.0
    private var activeAlerts: [UUID: AlertWindow] = [:]

    private init() {}

    private func showWindowWithFadeIn(_ window: NSWindow) {
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1.0
        }
    }

    func showAlert(title: String? = nil, message: String, informativeText: String? = nil, alertStyle: NSAlert.Style = .informational) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let mainWindow = NSApplication.shared.mainWindow else {
                let alert = NSAlert()
                alert.alertStyle = alertStyle
                alert.messageText = title ?? message
                if title != nil {
                    alert.informativeText = message + (informativeText.map { "\n" + $0 } ?? "")
                } else if let informativeText {
                    alert.informativeText = informativeText
                }
                alert.addButton(withTitle: L("Button_OK"))
                alert.runModal()
                return
            }

            let alertId = UUID()
            let mainWindowFrame = mainWindow.frame

            let messageHeight = AlertLayoutConstants.calculateTextHeight(
                text: message,
                width: AlertLayoutConstants.alertWidth - AlertLayoutConstants.padding * 2,
                font: AlertLayoutConstants.messageFont
            )

            var informativeHeight: CGFloat = 0
            if let informativeText {
                informativeHeight = AlertLayoutConstants.calculateTextHeight(
                    text: informativeText,
                    width: AlertLayoutConstants.alertWidth - AlertLayoutConstants.padding * 2,
                    font: AlertLayoutConstants.informativeFont
                )
                informativeHeight += AlertLayoutConstants.messageSpacing
            }

            let calculatedHeight = AlertLayoutConstants.padding + messageHeight + informativeHeight + AlertLayoutConstants.buttonBottomMargin + AlertLayoutConstants.buttonHeight + AlertLayoutConstants.padding
            let alertHeight = max(AlertLayoutConstants.minAlertHeight, calculatedHeight)

            let centerPosition = AlertLayoutConstants.calculateCenterPosition(
                width: AlertLayoutConstants.alertWidth,
                height: alertHeight,
                in: mainWindowFrame
            )

            let alertWindow = AlertWindow(
                frame: NSRect(x: centerPosition.x, y: centerPosition.y, width: AlertLayoutConstants.alertWidth, height: alertHeight),
                title: title,
                message: message,
                informativeText: informativeText,
                alertStyle: alertStyle,
                alertId: alertId
            )

            self.activeAlerts[alertId] = alertWindow
            self.showWindowWithFadeIn(alertWindow)

            DispatchQueue.main.asyncAfter(deadline: .now() + self.autoDismissDuration) { [weak self] in
                self?.dismissAlert(alertId: alertId)
            }
        }
    }

    private func dismissAlert(alertId: UUID) {
        guard let alertWindow = activeAlerts[alertId] else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            alertWindow.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            alertWindow.close()
            self?.activeAlerts.removeValue(forKey: alertId)
        })
    }

    func showPasswordDialog(message: String, informativeText: String? = nil, alertStyle: NSAlert.Style = .informational, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            guard let mainWindow = NSApplication.shared.mainWindow else {
                let alert = NSAlert()
                alert.alertStyle = alertStyle
                alert.messageText = message
                if let informativeText {
                    alert.informativeText = informativeText
                }
                alert.addButton(withTitle: L("Button_OK"))
                alert.addButton(withTitle: L("Button_Cancel"))

                let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                input.placeholderString = L("Password_Enter_Placeholder")
                alert.accessoryView = input
                alert.window.initialFirstResponder = input

                let response = alert.runModal()
                completion(response == .alertFirstButtonReturn ? input.stringValue : nil)
                return
            }

            let mainWindowFrame = mainWindow.frame
            let messageHeight = AlertLayoutConstants.calculateTextHeight(
                text: message,
                width: AlertLayoutConstants.alertWidth - AlertLayoutConstants.padding * 2,
                font: AlertLayoutConstants.messageFont
            )

            var informativeHeight: CGFloat = 0
            if let informativeText {
                informativeHeight = AlertLayoutConstants.calculateTextHeight(
                    text: informativeText,
                    width: AlertLayoutConstants.alertWidth - AlertLayoutConstants.padding * 2,
                    font: AlertLayoutConstants.informativeFont
                )
                informativeHeight += AlertLayoutConstants.messageSpacing
            }

            let calculatedHeight = AlertLayoutConstants.padding + messageHeight + informativeHeight + AlertLayoutConstants.inputTopMargin + AlertLayoutConstants.inputHeight + AlertLayoutConstants.buttonBottomMargin + AlertLayoutConstants.buttonHeight + AlertLayoutConstants.padding
            let alertHeight = max(AlertLayoutConstants.minPasswordDialogHeight, calculatedHeight)
            let centerPosition = AlertLayoutConstants.calculateCenterPosition(
                width: AlertLayoutConstants.alertWidth,
                height: alertHeight,
                in: mainWindowFrame
            )

            let passwordWindow = PasswordDialogWindow(
                frame: NSRect(x: centerPosition.x, y: centerPosition.y, width: AlertLayoutConstants.alertWidth, height: alertHeight),
                message: message,
                informativeText: informativeText,
                alertStyle: alertStyle,
                completion: completion
            )

            self.showWindowWithFadeIn(passwordWindow)
        }
    }
}

class AlertWindow: NSWindow {
    let alertId: UUID

    init(frame: NSRect, title: String?, message: String, informativeText: String?, alertStyle: NSAlert.Style, alertId: UUID) {
        self.alertId = alertId

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = title ?? L("Alert_Title")
        self.level = .floating
        self.backgroundColor = .windowBackgroundColor
        self.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        contentView.wantsLayer = true

        let messageHeight = AlertLayoutConstants.calculateTextHeight(
            text: message,
            width: frame.width - AlertLayoutConstants.padding * 2,
            font: AlertLayoutConstants.messageFont
        )

        var informativeHeight: CGFloat = 0
        if let informativeText {
            informativeHeight = AlertLayoutConstants.calculateTextHeight(
                text: informativeText,
                width: frame.width - AlertLayoutConstants.padding * 2,
                font: AlertLayoutConstants.informativeFont
            )
        }

        let messageY: CGFloat
        let informativeY: CGFloat
        if let informativeText, !informativeText.isEmpty {
            messageY = frame.height - AlertLayoutConstants.padding - messageHeight
            informativeY = messageY - AlertLayoutConstants.messageSpacing - informativeHeight
        } else {
            messageY = frame.height - AlertLayoutConstants.padding - messageHeight
            informativeY = 0
        }

        let messageField = NSTextField(wrappingLabelWithString: message)
        messageField.frame = NSRect(x: AlertLayoutConstants.padding, y: messageY, width: frame.width - AlertLayoutConstants.padding * 2, height: messageHeight)
        messageField.font = AlertLayoutConstants.messageFont
        messageField.textColor = .labelColor
        messageField.lineBreakMode = .byWordWrapping
        messageField.alignment = .left
        contentView.addSubview(messageField)

        if let informativeText, !informativeText.isEmpty {
            let infoField = NSTextField(wrappingLabelWithString: informativeText)
            infoField.frame = NSRect(x: AlertLayoutConstants.padding, y: informativeY, width: frame.width - AlertLayoutConstants.padding * 2, height: informativeHeight)
            infoField.font = AlertLayoutConstants.informativeFont
            infoField.textColor = .secondaryLabelColor
            infoField.lineBreakMode = .byWordWrapping
            infoField.alignment = .left
            contentView.addSubview(infoField)
        }

        let okButton = NSButton(frame: NSRect(x: frame.width - AlertLayoutConstants.padding - AlertLayoutConstants.buttonWidth, y: AlertLayoutConstants.buttonBottomMargin, width: AlertLayoutConstants.buttonWidth, height: AlertLayoutConstants.buttonHeight))
        okButton.title = L("Button_OK")
        okButton.bezelStyle = .rounded
        okButton.target = self
        okButton.action = #selector(closeWindow)
        contentView.addSubview(okButton)

        self.contentView = contentView
    }

    @objc private func closeWindow() {
        close()
    }
}

class PasswordDialogWindow: NSWindow {
    private var completion: ((String?) -> Void)?
    private var passwordField: NSSecureTextField?

    init(frame: NSRect, message: String, informativeText: String?, alertStyle: NSAlert.Style, completion: @escaping (String?) -> Void) {
        self.completion = completion

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = L("Alert_Title")
        self.level = .floating
        self.backgroundColor = .windowBackgroundColor
        self.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        contentView.wantsLayer = true

        let messageHeight = AlertLayoutConstants.calculateTextHeight(
            text: message,
            width: frame.width - AlertLayoutConstants.padding * 2,
            font: AlertLayoutConstants.messageFont
        )

        var informativeHeight: CGFloat = 0
        if let informativeText {
            informativeHeight = AlertLayoutConstants.calculateTextHeight(
                text: informativeText,
                width: frame.width - AlertLayoutConstants.padding * 2,
                font: AlertLayoutConstants.informativeFont
            )
        }

        let messageY: CGFloat
        let informativeY: CGFloat
        if let informativeText, !informativeText.isEmpty {
            messageY = frame.height - AlertLayoutConstants.padding - messageHeight
            informativeY = messageY - AlertLayoutConstants.messageSpacing - informativeHeight
        } else {
            messageY = frame.height - AlertLayoutConstants.padding - messageHeight
            informativeY = 0
        }

        let messageField = NSTextField(wrappingLabelWithString: message)
        messageField.frame = NSRect(x: AlertLayoutConstants.padding, y: messageY, width: frame.width - AlertLayoutConstants.padding * 2, height: messageHeight)
        messageField.font = AlertLayoutConstants.messageFont
        messageField.textColor = .labelColor
        messageField.lineBreakMode = .byWordWrapping
        messageField.alignment = .left
        contentView.addSubview(messageField)

        if let informativeText, !informativeText.isEmpty {
            let infoField = NSTextField(wrappingLabelWithString: informativeText)
            infoField.frame = NSRect(x: AlertLayoutConstants.padding, y: informativeY, width: frame.width - AlertLayoutConstants.padding * 2, height: informativeHeight)
            infoField.font = AlertLayoutConstants.informativeFont
            infoField.textColor = .secondaryLabelColor
            infoField.lineBreakMode = .byWordWrapping
            infoField.alignment = .left
            contentView.addSubview(infoField)
        }

        let inputY: CGFloat
        if let informativeText, !informativeText.isEmpty {
            inputY = informativeY - AlertLayoutConstants.inputTopMargin - AlertLayoutConstants.inputHeight
        } else {
            inputY = messageY - AlertLayoutConstants.inputTopMargin - AlertLayoutConstants.inputHeight
        }

        let passwordField = NSSecureTextField(frame: NSRect(x: AlertLayoutConstants.padding, y: inputY, width: frame.width - AlertLayoutConstants.padding * 2, height: AlertLayoutConstants.inputHeight))
        passwordField.placeholderString = L("Password_Enter_Placeholder")
        passwordField.delegate = self
        self.passwordField = passwordField
        contentView.addSubview(passwordField)

        let okButton = NSButton(frame: NSRect(x: frame.width - AlertLayoutConstants.padding - AlertLayoutConstants.buttonWidth * 2 - 8, y: AlertLayoutConstants.buttonBottomMargin, width: AlertLayoutConstants.buttonWidth, height: AlertLayoutConstants.buttonHeight))
        okButton.title = L("Button_OK")
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.target = self
        okButton.action = #selector(handleOK)
        contentView.addSubview(okButton)

        let cancelButton = NSButton(frame: NSRect(x: frame.width - AlertLayoutConstants.padding - AlertLayoutConstants.buttonWidth, y: AlertLayoutConstants.buttonBottomMargin, width: AlertLayoutConstants.buttonWidth, height: AlertLayoutConstants.buttonHeight))
        cancelButton.title = L("Button_Cancel")
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)
        contentView.addSubview(cancelButton)

        self.contentView = contentView

        DispatchQueue.main.async { [weak self] in
            self?.makeFirstResponder(passwordField)
        }
    }

    @objc private func handleOK() {
        let password = passwordField?.stringValue ?? ""
        completion?(password.isEmpty ? nil : password)
        closeWindow()
    }

    @objc private func handleCancel() {
        completion?(nil)
        closeWindow()
    }

    private func closeWindow() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.close()
        })
    }

    override func close() {
        completion = nil
        super.close()
    }
}

extension PasswordDialogWindow: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            handleOK()
            return true
        }
        return false
    }
}
