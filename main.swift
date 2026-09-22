import Cocoa
import ApplicationServices

// Local prototype. No audio capture, network, or keyboard content logging.
final class Bridge: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var window: NSWindow!
    let statusLabel = NSTextField(wrappingLabelWithString: "尚未启动")
    let countLabel = NSTextField(labelWithString: "")
    var startButton: NSButton!
    var learnButton: NSButton!
    var outputButton: NSButton!
    var modeButton: NSButton!
    var toggleMode = true
    var inputDownTime: TimeInterval?
    var lastDuration = "未测量"
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var enabled = false
    var held = false
    var learning = false
    var heldInput: String?
    var releaseTimer: Timer?
    var testTimer: Timer?
    var button: Int64 = 4
    var count = 0
    var status = "尚未启动"
    var sessionOutput = false
    let marker: Int64 = 0x4D564252

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.object(forKey: "button") != nil {
            button = Int64(UserDefaults.standard.integer(forKey: "button"))
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        makeWindow()
        rebuild()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }

    func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 510), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "鼠标语音桥"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "鼠标按住说话 · 测试版")
        title.font = .boldSystemFont(ofSize: 22)
        statusLabel.font = .systemFont(ofSize: 16)
        let instructions = NSTextField(wrappingLabelWithString: "Options+ 前侧键设为 F6；微信保持「按住 Fn 说话」。\n点按开关模式：点击侧键开始，再点击侧键结束。\n按住模式：按住侧键说话，松开结束。无需再识别侧键。")
        startButton = NSButton(title: "启动", target: self, action: #selector(toggle))
        learnButton = NSButton(title: "识别侧键", target: self, action: #selector(learn))
        outputButton = NSButton(title: "", target: self, action: #selector(output))
        modeButton = NSButton(title: "", target: self, action: #selector(changeMode))
        let actions = NSStackView(views: [startButton, learnButton, NSButton(title: "立即释放 Fn", target: self, action: #selector(emergency))])
        let bottom = NSStackView(views: [outputButton, NSButton(title: "使用说明", target: self, action: #selector(help)), NSButton(title: "退出", target: self, action: #selector(quit))])
        let test = NSButton(title: "独立测试 Fn（5 秒后按住，3 秒后释放）", target: self, action: #selector(testFn))
        let configure = NSButton(title: "配置 Options+：5 秒后发送 F6", target: self, action: #selector(configureF6))
        let stack = NSStackView(views: [title, instructions, statusLabel, countLabel, modeButton, actions, test, configure, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(row("显示鼠标语音桥", #selector(showWindow)))
        appMenu.addItem(row("退出", #selector(quit)))
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
        window.center()
        showWindow()
    }

    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }

    func row(_ title: String, _ action: Selector? = nil) -> NSMenuItem {
        let r = NSMenuItem(title: title, action: action, keyEquivalent: "")
        r.target = self
        return r
    }

    func rebuild() {
        item.button?.title = held ? "🎙 Fn↓" : "语音键"
        let menu = NSMenu()
        menu.addItem(row("鼠标语音桥 · 实验版"))
        menu.addItem(row(status))
        menu.addItem(row("收到触发：\(count) 次 · 侧键编号：\(button)"))
        menu.addItem(.separator())
        menu.addItem(row(enabled ? "暂停并释放 Fn" : "启动（需要辅助功能权限）", #selector(toggle)))
        menu.addItem(row(learning ? "取消识别侧键" : "识别侧键：点击后按一下前侧键", #selector(learn)))
        menu.addItem(row(sessionOutput ? "输出位置：Session（点击切换）" : "输出位置：HID（点击切换）", #selector(output)))
        menu.addItem(row("立即释放 Fn", #selector(emergency)))
        menu.addItem(.separator())
        menu.addItem(row("使用说明", #selector(help)))
        menu.addItem(row("退出", #selector(quit)))
        item.menu = menu
        statusLabel.stringValue = status
        countLabel.stringValue = "收到触发：\(count) 次 · 输入按住时长：\(lastDuration)"
        modeButton.title = toggleMode ? "模式：点按开关（点击切换）" : "模式：按住说话（点击切换）"
        startButton.title = enabled ? "暂停" : "启动"
        learnButton.title = learning ? "取消识别" : "识别侧键"
        outputButton.title = sessionOutput ? "输出：Session（切换）" : "输出：HID（切换）"
    }

    @objc func help() {
        let a = NSAlert()
        a.messageText = "先测试兼容性，再决定是否常用"
        a.informativeText = "微信输入法开启「按住说话」，设为 Fn。\n\n方式一：Options+ 前侧键恢复默认「前进」，本工具启动后选择「识别侧键」，再按前侧键。\n方式二：Options+ 前侧键映射 F6，本工具会将 F6 按下／松开转成 Fn。若 Options+ 只发送短促按键，不能持续按住说话。\n\n启动时由你在系统设置授予本工具辅助功能权限，再回到这里点击启动。请在空白文本编辑文档中测试。\n\n计数不增加：本工具未收到原始侧键或 F6。计数增加但微信不出现：尝试切换输出位置；仍失败则属于尚未解决的兼容问题。\n\n不采集音频，不联网，不保存输入文本。映射对所有鼠标生效；默认不接管后侧键。按住超过 60 秒自动释放；暂停、睡眠、退出也会释放。"
        a.runModal()
    }

    @objc func toggle() {
        if enabled { stop(); return }
        guard AXIsProcessTrusted() else {
            status = "请授权辅助功能后再次启动"
            rebuild()
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            return
        }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info = info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<Bridge>.fromOpaque(info).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = tap else {
            status = "监听创建失败；检查权限并重新启动程序"
            rebuild(); return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        enabled = true
        status = "已启动，等待侧键或 F6"
        rebuild()
    }

    func stop() {
        releaseFn()
        learning = false
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; enabled = false
        status = "已暂停"
        rebuild()
    }

    @objc func learn() {
        guard enabled else { status = "先启动，再识别侧键"; rebuild(); return }
        releaseFn()
        learning.toggle()
        status = learning ? "请按一下前侧键（不按后侧键）" : "已取消识别"
        rebuild()
    }
    @objc func output() { releaseFn(); sessionOutput.toggle(); rebuild() }
    @objc func changeMode() { releaseFn(); inputDownTime = nil; toggleMode.toggle(); status = "模式已切换"; rebuild() }
    @objc func configureF6() {
        guard AXIsProcessTrusted() else { status = "请先点击启动检查辅助功能权限"; rebuild(); return }
        stop()
        status = "5 秒内点击 Options+ 的快捷键录入框"; rebuild()
        testTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let source = CGEventSource(stateID: .privateState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 97, keyDown: down)
                event?.flags = [.maskSecondaryFn]
                event?.setIntegerValueField(.keyboardEventKeyboardType, value: 40)
                event?.setIntegerValueField(.eventSourceUserData, value: self.marker)
                event?.post(tap: .cghidEventTap)
            }
            self.status = "已发送 F6；确认 Options+ 显示 F6 后点启动"; self.rebuild()
        }
    }
    @objc func testFn() {
        guard AXIsProcessTrusted() else { status = "测试前请先点击启动检查辅助功能权限"; rebuild(); return }
        releaseFn(); learning = false
        status = "5 秒后测试 Fn，请立即点击一个空白输入框"
        rebuild()
        testTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.held = true; self.heldInput = "test"; self.sendFn(true)
            self.status = "测试：已发送 Fn↓，3 秒后释放"; self.rebuild()
            self.releaseTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.releaseFn(); self.status = "Fn 测试结束；请确认微信语音面板是否出现"; self.rebuild()
            }
        }
    }
    @objc func emergency() { releaseFn(); status = "已释放 Fn"; rebuild() }
    @objc func sleeping() { stop() }
    @objc func quit() { stop(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { releaseFn() }

    func sendFn(_ down: Bool) {
        let s = CGEventSource(stateID: .privateState)
        guard let e = CGEvent(keyboardEventSource: s, virtualKey: 63, keyDown: down) else { return }
        e.type = .flagsChanged
        var flags = CGEventSource.flagsState(.hidSystemState)
        if down { flags.insert(.maskSecondaryFn) } else { flags.remove(.maskSecondaryFn) }
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        e.post(tap: sessionOutput ? .cgSessionEventTap : .cghidEventTap)
    }
    func releaseFn() {
        testTimer?.invalidate(); testTimer = nil
        releaseTimer?.invalidate(); releaseTimer = nil
        if held { sendFn(false) }
        held = false; heldInput = nil
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Disable safely instead of silently continuing after losing a release.
            releaseFn()
            DispatchQueue.main.async { self.stop(); self.status = "监听中断，已暂停；可手动重新启动"; self.rebuild() }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == marker { return Unmanaged.passUnretained(event) }
        let mouse = type == .otherMouseDown || type == .otherMouseUp
        let down = type == .otherMouseDown || type == .keyDown
        let n = event.getIntegerValueField(mouse ? .mouseEventButtonNumber : .keyboardEventKeycode)
        if learning && mouse && down && n >= 3 {
            button = n; learning = false
            UserDefaults.standard.set(Int(n), forKey: "button")
            status = "已识别侧键 \(n)，请再按住测试"
            DispatchQueue.main.async { self.rebuild() }
            return nil
        }
        // F6 virtual key = 97. Other keyboard events are neither stored nor transformed.
        guard enabled, !learning, (mouse ? n == button : n == 97) else { return Unmanaged.passUnretained(event) }
        // Repeated F6 keydowns must not restart Fn after the safety timeout.
        if !mouse && down && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
        let input = mouse ? "mouse" : "F6"
        if down { inputDownTime = ProcessInfo.processInfo.systemUptime }
        if !down, let began = inputDownTime {
            lastDuration = String(format: "%.0f ms", (ProcessInfo.processInfo.systemUptime - began) * 1000)
            inputDownTime = nil
            if toggleMode {
                count += 1
                // Let the source key-up finish before posting the replacement modifier.
                testTimer?.invalidate()
                testTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
                    guard let self = self, self.enabled else { return }
                    if self.held {
                        self.releaseFn(); self.status = "已发送 Fn↑，结束语音"
                    } else {
                        self.held = true; self.heldInput = input; self.sendFn(true)
                        self.status = "已发送 Fn↓；再点侧键结束（最长 60 秒）"
                        self.releaseTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                            guard let self = self else { return }
                            self.releaseFn(); self.status = "超过 60 秒，已自动释放"; self.rebuild()
                        }
                    }
                    self.rebuild()
                }
            }
        }
        if toggleMode { DispatchQueue.main.async { self.rebuild() }; return nil }
        if down && !held {
            held = true; heldInput = input; count += 1
            sendFn(true)
            status = "收到 \(input) 按下，已发送 Fn↓"
            releaseTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.releaseFn(); self.status = "超过 60 秒，已自动释放"; self.rebuild()
            }
        } else if !down && heldInput == input {
            releaseFn(); status = "收到松开，已发送 Fn↑"
        }
        DispatchQueue.main.async { self.rebuild() }
        return nil
    }
}

let app = NSApplication.shared
let bridge = Bridge()
app.delegate = bridge
app.setActivationPolicy(.regular)
app.run()
