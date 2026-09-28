import Cocoa
import ServiceManagement

// MARK: - Duration parsing

/// Accepts: "25" (minutes), "5:30" (m:s), "1:05:00" (h:m:s),
/// "1h30m", "90s", "1시간 20분", "30초".
func parseDuration(_ raw: String) -> TimeInterval? {
    let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    if s.isEmpty { return nil }

    if let minutes = Double(s) {
        return minutes > 0 ? minutes * 60 : nil
    }

    if s.contains(":") {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        let v = parts.map { $0! }
        let seconds = v.count == 3 ? v[0] * 3600 + v[1] * 60 + v[2] : v[0] * 60 + v[1]
        return seconds > 0 ? seconds : nil
    }

    let pattern = "(\\d+(?:\\.\\d+)?)\\s*(hours|hour|hrs|hr|h|시간|minutes|minute|mins|min|m|분|seconds|second|secs|sec|s|초)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = s as NSString
    let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return nil }

    // Reject input with leftover text that isn't a number+unit pair.
    let leftover = regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    guard leftover.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

    var total: TimeInterval = 0
    for m in matches {
        let value = Double(ns.substring(with: m.range(at: 1))) ?? 0
        switch ns.substring(with: m.range(at: 2)) {
        case "hours", "hour", "hrs", "hr", "h", "시간": total += value * 3600
        case "seconds", "second", "secs", "sec", "s", "초": total += value
        default: total += value * 60
        }
    }
    return total > 0 ? total : nil
}

func formatTime(_ interval: TimeInterval) -> String {
    let t = max(0, Int(interval.rounded(.up)))
    let h = t / 3600, m = (t % 3600) / 60, s = t % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSTextFieldDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let field = NSTextField()
    private let hintLabel = NSTextField(labelWithString: "")
    private var pauseItem: NSMenuItem!
    private var resetItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private var ticker: Timer?
    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var alarm: NSSound?
    private var isAlarming = false

    private let defaultHint = "예: 25, 5:30, 1h30m, 10분 30초"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        statusItem.menu = menu
        render()
    }

    private func buildMenu() {
        menu.delegate = self

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 52))
        field.frame = NSRect(x: 14, y: 22, width: 212, height: 24)
        field.placeholderString = "시간 입력 후 Enter"
        field.bezelStyle = .roundedBezel
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.delegate = self
        field.target = self
        field.action = #selector(startFromField)
        hintLabel.frame = NSRect(x: 16, y: 3, width: 212, height: 16)
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.stringValue = defaultHint
        container.addSubview(field)
        container.addSubview(hintLabel)

        let fieldItem = NSMenuItem()
        fieldItem.view = container
        menu.addItem(fieldItem)
        menu.addItem(.separator())

        pauseItem = NSMenuItem(title: "일시정지", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        resetItem = NSMenuItem(title: "초기화", action: #selector(reset), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        menu.autoenablesItems = false
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        hintLabel.stringValue = defaultHint
        hintLabel.textColor = .secondaryLabelColor
        updateMenuItems()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.field.window?.makeFirstResponder(self.field)
            self.field.selectText(nil)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            startFromField()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            menu.cancelTracking()
            return true
        }
        return false
    }

    private func updateMenuItems() {
        let active = endDate != nil || pausedRemaining != nil
        pauseItem.isEnabled = active
        pauseItem.title = pausedRemaining != nil ? "계속" : "일시정지"
        resetItem.isEnabled = active || isAlarming
        resetItem.title = isAlarming ? "알람 끄기" : "초기화"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "설정을 바꾸지 못했어요"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal() // one-off, user-initiated click — not on the finish() hot path, safe to block here
        }
        updateMenuItems()
    }

    // MARK: Timer control

    @objc private func startFromField() {
        guard let duration = parseDuration(field.stringValue) else {
            hintLabel.stringValue = "형식 오류 — " + defaultHint
            hintLabel.textColor = .systemRed
            NSSound.beep()
            return
        }
        start(duration)
        menu.cancelTracking()
    }

    private func start(_ duration: TimeInterval) {
        stopAlarm()
        isAlarming = false
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(duration)
        startTicker()
        render()
    }

    @objc private func togglePause() {
        if let remaining = pausedRemaining {
            pausedRemaining = nil
            endDate = Date().addingTimeInterval(remaining)
            startTicker()
        } else if let end = endDate {
            pausedRemaining = end.timeIntervalSinceNow
            endDate = nil
            ticker?.invalidate()
        }
        render()
    }

    @objc private func reset() {
        ticker?.invalidate()
        endDate = nil
        pausedRemaining = nil
        isAlarming = false
        stopAlarm()
        render()
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard let end = endDate else { return }
        if end.timeIntervalSinceNow <= 0 {
            finish()
        } else {
            render()
        }
    }

    // NOTE: deliberately non-blocking. An NSAlert.runModal() here used to
    // freeze the whole app (menu stopped opening, Pause/Quit stopped
    // responding) whenever the modal window failed to surface above other
    // apps/spaces. A looping sound + a menu item to silence it is more
    // reliable for a menu-bar-only (accessory) app.
    private func finish() {
        ticker?.invalidate()
        endDate = nil
        isAlarming = true
        render(finished: true)

        alarm = NSSound(named: "Glass")
        alarm?.loops = true
        alarm?.play()

        postFinishedNotification()
    }

    private func postFinishedNotification() {
        let note = NSUserNotification()
        note.title = "⏰ 타이머 종료"
        note.informativeText = "메뉴에서 \"알람 끄기\"를 누르면 소리가 멈춰요."
        NSUserNotificationCenter.default.deliver(note)
    }

    private func stopAlarm() {
        alarm?.stop()
        alarm = nil
    }

    // MARK: Status bar rendering

    private func render(finished: Bool = false) {
        guard let button = statusItem.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        let text: String
        if finished {
            text = "⏰ 00:00"
        } else if let remaining = pausedRemaining {
            text = "⏸ " + formatTime(remaining)
        } else if let end = endDate {
            text = formatTime(end.timeIntervalSinceNow)
        } else {
            text = ""
        }

        if text.isEmpty {
            let icon = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer")
            icon?.isTemplate = true // adapt to light/dark menu bar; without this it can render invisible
            button.image = icon
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            button.image = nil
            button.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
        }
        updateMenuItems()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
