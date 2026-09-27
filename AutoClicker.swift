import AppKit
import ApplicationServices

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let naturalHeight = cellSize(forBounds: rect).height
        let heightDifference = drawingRect.height - naturalHeight
        if heightDifference > 0 {
            drawingRect.origin.y += floor(heightDifference / 2)
            drawingRect.size.height = naturalHeight
        }
        return drawingRect
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        start selectionStart: Int,
        length selectionLength: Int
    ) {
        super.select(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            start: selectionStart,
            length: selectionLength
        )
    }
}

final class StatusPillView: NSView {
    var text = "" {
        didSet { needsDisplay = true }
    }

    var fillColor = NSColor.systemGray.withAlphaComponent(0.34) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        fillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = NSRect(
            x: 0,
            y: floor((bounds.height - textSize.height) / 2),
            width: bounds.width,
            height: ceil(textSize.height)
        )
        attributedText.draw(in: textRect)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var intervalField: NSTextField!
    private var startButton: NSButton!
    private var statusPillView: StatusPillView!
    private var countLabel: NSTextField!
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var running = false
    private var pausedForPointerInsideWindow = false
    private var clickCount = 0
    private var countdown = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureDockIcon()
        buildWindow()
        installHotkeys()
        updateAccessibilityStatus()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopClicking(message: "已停止")
        if let monitor = globalKeyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 150),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "鼠标快点"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        let content = NSView()
        window.contentView = content

        let title = label("鼠标快点", size: 19, weight: .semibold)
        let intervalUnit = NSTextField()
        intervalUnit.cell = VerticallyCenteredTextFieldCell(textCell: "毫秒")
        intervalUnit.alignment = .center
        intervalUnit.font = .systemFont(ofSize: 11, weight: .medium)
        intervalUnit.textColor = .secondaryLabelColor
        intervalUnit.isEditable = false
        intervalUnit.isSelectable = false
        intervalUnit.isBezeled = false
        intervalUnit.drawsBackground = false

        intervalField = NSTextField()
        intervalField.cell = VerticallyCenteredTextFieldCell(textCell: "1000")
        intervalField.stringValue = "1000"
        intervalField.alignment = .center
        intervalField.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        intervalField.placeholderString = "最短 50"
        intervalField.target = self
        intervalField.action = #selector(validateInterval)
        intervalField.isBezeled = false
        intervalField.drawsBackground = false
        intervalField.focusRingType = .none

        startButton = NSButton(title: "3 秒后开始", target: self, action: #selector(toggleClicking))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        applyStartButtonAppearance()

        statusPillView = StatusPillView()
        setStatus("等待开始", color: .systemGray)
        countLabel = label("已点击 0 次", size: 11, color: .secondaryLabelColor)
        countLabel.alignment = .right

        let intervalRow = NSView()
        intervalRow.translatesAutoresizingMaskIntoConstraints = false
        intervalRow.wantsLayer = true
        intervalRow.layer?.cornerRadius = 9
        intervalRow.layer?.borderWidth = 2
        intervalRow.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.72).cgColor
        intervalRow.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.32).cgColor
        intervalRow.layer?.masksToBounds = true
        intervalField.translatesAutoresizingMaskIntoConstraints = false
        intervalUnit.translatesAutoresizingMaskIntoConstraints = false
        let intervalInputGroup = NSStackView(views: [intervalField, intervalUnit])
        intervalInputGroup.orientation = .horizontal
        intervalInputGroup.alignment = .centerY
        intervalInputGroup.spacing = 4
        intervalInputGroup.translatesAutoresizingMaskIntoConstraints = false
        intervalRow.addSubview(intervalInputGroup)

        let bottomRow = NSStackView(views: [statusPillView, countLabel])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.distribution = .fillEqually
        bottomRow.spacing = 8

        let stack = NSStackView(views: [title, intervalRow, startButton, bottomRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 9
        stack.setCustomSpacing(11, after: intervalRow)
        stack.setCustomSpacing(11, after: startButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        intervalRow.widthAnchor.constraint(equalToConstant: 150).isActive = true
        intervalRow.heightAnchor.constraint(equalToConstant: 28).isActive = true
        intervalField.widthAnchor.constraint(equalToConstant: 75).isActive = true
        intervalField.heightAnchor.constraint(equalToConstant: 28).isActive = true
        intervalUnit.widthAnchor.constraint(equalToConstant: 30).isActive = true
        intervalUnit.heightAnchor.constraint(equalToConstant: 28).isActive = true
        startButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        startButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        statusPillView.heightAnchor.constraint(equalToConstant: 20).isActive = true
        bottomRow.widthAnchor.constraint(equalToConstant: 150).isActive = true
        NSLayoutConstraint.activate([
            intervalInputGroup.centerXAnchor.constraint(equalTo: intervalRow.centerXAnchor),
            intervalInputGroup.centerYAnchor.constraint(equalTo: intervalRow.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 11)
        ])
    }

    private func configureDockIcon() {
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }

        NSApp.applicationIconImage = icon
    }

    private func applyStartButtonAppearance() {
        startButton.title = "3 秒后开始"
        startButton.bezelColor = .systemGreen
        startButton.contentTintColor = .white
    }

    private func applyStopButtonAppearance(title: String) {
        startButton.title = title
        startButton.bezelColor = .systemRed
        startButton.contentTintColor = .white
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusPillView.text = text
        statusPillView.fillColor = color.withAlphaComponent(0.34)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            setStatus("需要辅助功能权限", color: .systemRed)
        }
    }

    private func updateAccessibilityStatus() {
        if AXIsProcessTrusted() {
            setStatus("等待开始", color: .systemGray)
        } else {
            setStatus("需要辅助功能权限", color: .systemRed)
        }
    }

    private func isAccessibilityAllowed() -> Bool {
        AXIsProcessTrusted()
    }

    @objc private func validateInterval() {
        intervalField.stringValue = String(intervalMilliseconds())
    }

    private func intervalMilliseconds() -> Int {
        max(50, min(3_600_000, Int(intervalField.stringValue) ?? 1000))
    }

    @objc private func toggleClicking() {
        if running || countdownTimer != nil {
            stopClicking(message: "已停止")
        } else {
            beginCountdown()
        }
    }

    private func beginCountdown() {
        guard isAccessibilityAllowed() else {
            requestAccessibilityPermission()
            setStatus("授权后重试", color: .systemRed)
            return
        }

        validateInterval()
        countdown = 3
        clickCount = 0
        countLabel.stringValue = "已点击 0 次"
        applyStopButtonAppearance(title: "取消")
        setStatus("\(countdown) 秒后开始", color: .systemOrange)

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.countdown -= 1
            if self.countdown <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.startClicking()
            } else {
                self.setStatus("\(self.countdown) 秒后开始", color: .systemOrange)
            }
        }
    }

    private func startClicking() {
        running = true
        pausedForPointerInsideWindow = false
        applyStopButtonAppearance(title: "停止点击")
        setStatus("运行中", color: .systemGreen)

        let seconds = Double(intervalMilliseconds()) / 1000.0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            self?.performClick()
        }
    }

    private func performClick() {
        guard running else { return }
        let location = NSEvent.mouseLocation

        if window.frame.contains(location) {
            if !pausedForPointerInsideWindow {
                pausedForPointerInsideWindow = true
                setStatus("面板内暂停", color: .systemOrange)
            }
            return
        }

        if pausedForPointerInsideWindow {
            pausedForPointerInsideWindow = false
            setStatus("运行中", color: .systemGreen)
        }

        guard let screen = NSScreen.screens.first else { return }
        let quartzPoint = CGPoint(x: location.x, y: screen.frame.maxY - location.y)

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: quartzPoint, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: quartzPoint, mouseButton: .left)
        else { return }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        clickCount += 1
        countLabel.stringValue = "已点击 \(clickCount) 次"
    }

    private func stopClicking(message: String) {
        running = false
        pausedForPointerInsideWindow = false
        timer?.invalidate()
        timer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        if startButton != nil {
            applyStartButtonAppearance()
        }
        if statusPillView != nil {
            setStatus(message, color: message == "紧急停止" ? .systemRed : .systemGray)
        }
    }

    private func installHotkeys() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.modifierFlags.contains([.option, .shift]) else { return }
            if event.keyCode == 1 { // S
                self?.toggleClicking()
            } else if event.keyCode == 7 { // X
                self?.stopClicking(message: "已紧急停止")
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.option, .shift]), event.keyCode == 1 || event.keyCode == 7 {
                handler(event)
                return nil
            }
            return event
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
