// Blue View OS for macOS: a menu bar app with the live sky desktop and window tiling.
//
// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
//
//   Live sky desktop     the Blue View sky (real sun, moon, stars, satellites and
//                        weather) behind your windows and desktop icons
//   Screensaver          the sky with the logo, clock and forecast after you've
//                        been away (works on every macOS version, including those
//                        where third-party .saver web views go blank)
//   Option + Shift + T   tile every window on the screen under the pointer in an
//                        even grid; press again to put them back where they were
//                        (Control + Option + T on macOS 15.0 and 15.1, which
//                        don't allow Option + Shift shortcuts)
//   Drag a tile          onto another tile (a glass outline marks it) to swap them
//
// Moving other apps' windows needs the Accessibility permission.

import AppKit
import ApplicationServices
import Carbon
import IOKit.pwr_mgt
import ServiceManagement
import WebKit

/// A window showing the web sky (Resources/sky) with the given settings.
func makeSkyWebView(frame: NSRect, query: String) -> WKWebView? {
    guard let sky = Bundle.main.url(forResource: "sky", withExtension: nil) else { return nil }
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.addUserScript(
        WKUserScript(source: "window.BVOS_QUERY = '\(query)';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
    let web = WKWebView(frame: frame, configuration: configuration)
    web.autoresizingMask = [.width, .height]
    web.loadFileURL(sky.appendingPathComponent("index.html"), allowingReadAccessTo: sky)
    return web
}

// MARK: - Accessibility windows

/// Screen geometry: AppKit puts the origin at the bottom left of the main screen,
/// Accessibility at its top left.
enum Coordinates {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func toAX(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func fromAX(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

struct AXWindow: Equatable {
    let element: AXUIElement
    let app: AXUIElement

    static func == (a: AXWindow, b: AXWindow) -> Bool { CFEqual(a.element, b.element) }

    private func value<T>(_ attribute: String, _ type: AXValueType, _ empty: T) -> T {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success, let raw,
              CFGetTypeID(raw) == AXValueGetTypeID() else { return empty }
        var result = empty
        AXValueGetValue(raw as! AXValue, type, &result)
        return result
    }

    private func flag(_ attribute: String) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return false }
        return (raw as? Bool) ?? false
    }

    /// Frame in AppKit coordinates.
    var frame: CGRect {
        let origin = value(kAXPositionAttribute, .cgPoint, CGPoint.zero)
        let size = value(kAXSizeAttribute, .cgSize, CGSize.zero)
        return Coordinates.fromAX(CGRect(origin: origin, size: size))
    }

    var isTileable: Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == (kAXStandardWindowSubrole as String) &&
            !flag(kAXMinimizedAttribute) && !flag("AXFullScreen") && frame.width > 0 && frame.height > 0
    }

    /// Moves the window so its frame (AppKit coordinates) is `rect`.
    func setFrame(_ rect: CGRect) {
        // Chrome and Electron apps animate every change while this is on; turn it off meanwhile.
        var enhanced: CFTypeRef?
        let hadEnhanced = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &enhanced) == .success && (enhanced as? Bool) == true
        if hadEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }

        let ax = Coordinates.toAX(rect)
        var origin = ax.origin, size = ax.size
        if let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) {
            // Size, position, then size again: macOS clamps sizes to the display the window is on.
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, originValue)
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        }

        if hadEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    /// Standard windows of regular apps on the current Space whose center is on `screen`.
    static func onScreen(_ screen: NSScreen) -> [AXWindow] {
        var result: [AXWindow] = []
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular && !running.isHidden {
            if running.processIdentifier == ProcessInfo.processInfo.processIdentifier { continue }
            let app = AXUIElementCreateApplication(running.processIdentifier)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
                  let elements = raw as? [AXUIElement] else { continue }
            for element in elements {
                let window = AXWindow(element: element, app: app)
                let frame = window.frame
                if window.isTileable && screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                    result.append(window)
                }
            }
        }
        return result
    }

    /// The window under a point (AppKit coordinates), if any.
    static func at(_ point: CGPoint) -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        let ax = Coordinates.toAX(CGRect(origin: point, size: .zero)).origin
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(ax.x), Float(ax.y), &hit) == .success, var element = hit else { return nil }

        // Walk up from the control under the pointer to its window.
        for _ in 0..<32 {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if (role as? String) == (kAXWindowRole as String) { break }
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) == .success, let window {
                element = window as! AXUIElement
                break
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success, let parent else { return nil }
            element = parent as! AXUIElement
        }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return AXWindow(element: element, app: AXUIElementCreateApplication(pid))
    }
}

// MARK: - Tiling

final class Tile {
    let window: AXWindow
    let before: CGRect // where it was before tiling
    var cell: CGRect   // its tile

    init(window: AXWindow, before: CGRect, cell: CGRect) {
        self.window = window
        self.before = before
        self.cell = cell
    }
}

final class Tiler {
    private var tiles: [Tile] = []
    private let outline = TileOutline()
    private var dragging: Tile?
    private var dragStartFrame = CGRect.zero
    private var dropTarget: Tile?
    private var monitors: [Any] = []

    init() {
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in self?.handle(event) }) {
            monitors.append(monitor)
        }
    }

    // Tile all / put back.

    func toggle() {
        guard AXIsProcessTrusted() else {
            Permissions.request()
            return
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let windows = AXWindow.onScreen(screen)

        if !tiles.isEmpty && allInPlace(windows) {
            putBack()
        } else {
            tileAll(windows, on: screen)
        }
    }

    private func find(_ window: AXWindow) -> Tile? {
        tiles.first { $0.window == window }
    }

    private func allInPlace(_ windows: [AXWindow]) -> Bool {
        windows.allSatisfy { window in
            guard let tile = find(window) else { return false }
            return near(window.frame, tile.cell)
        }
    }

    private func tileAll(_ windows: [AXWindow], on screen: NSScreen) {
        guard !windows.isEmpty else { return }
        let gap: CGFloat = 8
        let area = screen.visibleFrame.insetBy(dx: gap, dy: gap)

        // Keep the order people see: top to bottom, then left to right.
        let band = max(1, area.height / 4)
        let ordered = windows.sorted { a, b in
            let rowA = Int((screen.frame.maxY - a.frame.maxY) / band), rowB = Int((screen.frame.maxY - b.frame.maxY) / band)
            return rowA != rowB ? rowA < rowB : a.frame.minX < b.frame.minX
        }

        let count = ordered.count
        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))

        var next: [Tile] = []
        var index = 0
        for row in 0..<rows {
            let inRow = row == rows - 1 ? count - columns * (rows - 1) : columns
            for column in 0..<inRow {
                let width = (area.width - gap * CGFloat(inRow - 1)) / CGFloat(inRow)
                let height = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
                // Rows count down from the top of the screen.
                let cell = CGRect(x: area.minX + CGFloat(column) * (width + gap),
                                  y: area.maxY - CGFloat(row + 1) * height - CGFloat(row) * gap,
                                  width: width, height: height).integral
                let window = ordered[index]
                next.append(Tile(window: window, before: find(window)?.before ?? window.frame, cell: cell))
                index += 1
            }
        }

        tiles = next
        for tile in tiles { tile.window.setFrame(tile.cell) }
    }

    private func putBack() {
        for tile in tiles { tile.window.setFrame(tile.before) }
        tiles.removeAll()
    }

    private func near(_ a: CGRect, _ b: CGRect) -> Bool {
        let slack: CGFloat = 12
        return abs(a.minX - b.minX) <= slack && abs(a.minY - b.minY) <= slack &&
            abs(a.maxX - b.maxX) <= slack && abs(a.maxY - b.maxY) <= slack
    }

    // Swap by drag.

    private func handle(_ event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            dropTarget = nil
            dragging = nil
            guard !tiles.isEmpty, AXIsProcessTrusted(), let window = AXWindow.at(pointer), let tile = find(window) else { return }
            dragging = tile
            dragStartFrame = window.frame

        case .leftMouseDragged:
            guard let dragging else { return }
            // Only a moved window counts as a drag, not a resize or a click inside it.
            let frame = dragging.window.frame
            guard frame.size.equalTo(dragStartFrame.size), !frame.origin.equalTo(dragStartFrame.origin) else { return }
            let over = tiles.first { $0 !== dragging && $0.cell.contains(pointer) }
            if over !== dropTarget {
                dropTarget = over
                if let over { outline.show(over.cell) } else { outline.hide() }
            }

        case .leftMouseUp:
            outline.hide()
            defer { dragging = nil; dropTarget = nil }
            guard let dragged = dragging, let target = dropTarget else { return }
            swap(&dragged.cell, &target.cell)
            // Let the window server finish the drag before moving the windows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                dragged.window.setFrame(dragged.cell)
                target.window.setFrame(target.cell)
            }

        default:
            break
        }
    }
}

// MARK: - Glass outline

/// A clear glass panel over the tile a dragged window will swap with. It ignores the mouse.
final class TileOutline {
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor(calibratedRed: 0.22, green: 0.71, blue: 1.0, alpha: 0.55).cgColor
        glass.layer?.backgroundColor = NSColor(calibratedRed: 0.22, green: 0.71, blue: 1.0, alpha: 0.12).cgColor
        panel.contentView = glass
    }

    func show(_ rect: CGRect) {
        panel.setFrame(rect, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

// MARK: - Hotkey

/// A system-wide hotkey through Carbon, which needs no extra permission.
final class Hotkey {
    private static var action: (() -> Void)?
    private var reference: EventHotKeyRef?
    private(set) var label = ""

    init(_ action: @escaping () -> Void) {
        Hotkey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Hotkey.action?() }
            return noErr
        }, 1, &spec, nil, nil)

        // macOS 15.0 and 15.1 refuse shortcuts that use only Option and Shift.
        let choices: [(UInt32, String)] = [(UInt32(optionKey | shiftKey), "⌥⇧T"), (UInt32(controlKey | optionKey), "⌃⌥T")]
        for (modifiers, name) in choices {
            let id = EventHotKeyID(signature: OSType(0x4256_4F53), id: 1) // 'BVOS'
            if RegisterEventHotKey(UInt32(kVK_ANSI_T), modifiers, id, GetApplicationEventTarget(), 0, &reference) == noErr {
                label = name
                break
            }
        }
    }
}

// MARK: - Permission

enum Permissions {
    static func request() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Live sky desktop

/// The web sky (Resources/sky, the same page as the Windows and Omarchy skies) in a
/// window at desktop level on every screen: above the wallpaper, below desktop icons.
final class SkyDesktop {
    private var windows: [NSWindow] = []
    private static let key = "LiveSkyDesktop"

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.key)
            rebuild()
        }
    }

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
        rebuild()
    }

    func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard isEnabled else { return }

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.hasShadow = false

            guard let web = makeSkyWebView(frame: NSRect(origin: .zero, size: screen.frame.size), query: "fps=24") else { return }
            window.contentView = web

            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }
}

// MARK: - Screensaver

/// The sky with the logo, clock and forecast, full screen on every display after the
/// computer has been idle. Any key, click or real mouse movement closes it.
final class SkyScreensaver {
    static let minutesKey = "ScreensaverMinutes"
    private var windows: [NSWindow] = []
    private var monitors: [Any] = []
    private var timer: Timer?
    private var shownAt = Date.distantPast
    private var startPointer = CGPoint.zero

    var minutes: Int {
        get { UserDefaults.standard.object(forKey: Self.minutesKey) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: Self.minutesKey) }
    }

    var isShowing: Bool { !windows.isEmpty }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.hide() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.hide()
        }
    }

    private static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Something (a video, a presentation) is keeping the display awake.
    private static func displayKeptAwake() -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&assertions) == kIOReturnSuccess,
              let status = assertions?.takeRetainedValue() as? [String: Int] else { return false }
        return (status[kIOPMAssertionTypePreventUserIdleDisplaySleep] ?? 0) > 0
    }

    private func check() {
        guard minutes > 0, !isShowing else { return }
        if Self.idleSeconds() >= TimeInterval(minutes * 60) && !Self.displayKeptAwake() {
            show()
        }
    }

    func show() {
        guard !isShowing else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.alphaValue = 0
            guard let web = makeSkyWebView(frame: NSRect(origin: .zero, size: screen.frame.size), query: "overlay=1&fps=30") else { return }
            window.contentView = web
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.5
            windows.forEach { $0.animator().alphaValue = 1 }
        }
        NSCursor.hide()
        shownAt = Date()
        startPointer = NSEvent.mouseLocation

        let events: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .scrollWheel]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in self?.input(event) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in self?.input(event); return nil }) {
            monitors.append(local)
        }
    }

    private func input(_ event: NSEvent) {
        // Showing full-screen windows can itself look like input for a moment.
        guard Date().timeIntervalSince(shownAt) > 1.2 else { return }
        if event.type == .mouseMoved {
            let pointer = NSEvent.mouseLocation
            guard abs(pointer.x - startPointer.x) + abs(pointer.y - startPointer.y) > 12 else { return }
        }
        hide()
    }

    func hide() {
        guard isShowing else { return }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.unhide()
    }
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let tiler = Tiler()
    private var sky: SkyDesktop!
    private var screensaver: SkyScreensaver!
    private let screensaverMenu = NSMenu()
    private var hotkey: Hotkey!
    private let tileItem = NSMenuItem(title: "Tile All Windows", action: #selector(tile), keyEquivalent: "")
    private let skyItem = NSMenuItem(title: "Live Sky Desktop", action: #selector(toggleSky), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Allow Window Tiling in Accessibility…", action: #selector(openPermissions), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkey = Hotkey { [weak self] in self?.tiler.toggle() }
        sky = SkyDesktop()
        screensaver = SkyScreensaver()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.logo()
        statusItem.button?.toolTip = "Blue View OS"

        let menu = NSMenu()
        menu.delegate = self
        for item in [tileItem, skyItem, loginItem, permissionItem] { item.target = self }
        menu.addItem(tileItem)
        menu.addItem(skyItem)

        let screensaverItem = NSMenuItem(title: "Screensaver", action: nil, keyEquivalent: "")
        for (title, value) in [("Off", 0), ("After 2 Minutes", 2), ("After 5 Minutes", 5), ("After 10 Minutes", 10), ("After 20 Minutes", 20)] {
            let item = NSMenuItem(title: title, action: #selector(setScreensaver(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            screensaverMenu.addItem(item)
        }
        screensaverMenu.addItem(.separator())
        let showNow = NSMenuItem(title: "Show Now", action: #selector(showScreensaver), keyEquivalent: "")
        showNow.target = self
        screensaverMenu.addItem(showNow)
        screensaverItem.submenu = screensaverMenu
        menu.addItem(screensaverItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Blue View OS", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        // Open at login from the first launch on; the menu can turn it off.
        if !UserDefaults.standard.bool(forKey: "DidSetUpLogin") {
            UserDefaults.standard.set(true, forKey: "DidSetUpLogin")
            try? SMAppService.mainApp.register()
        }

        if !AXIsProcessTrusted() { Permissions.request() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        tileItem.title = hotkey.label.isEmpty ? "Tile All Windows" : "Tile All Windows   \(hotkey.label)"
        skyItem.state = sky.isEnabled ? .on : .off
        for item in screensaverMenu.items where item.action == #selector(setScreensaver(_:)) {
            item.state = item.tag == screensaver.minutes ? .on : .off
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permissionItem.isHidden = AXIsProcessTrusted()
    }

    @objc private func tile() { tiler.toggle() }
    @objc private func toggleSky() { sky.isEnabled.toggle() }
    @objc private func setScreensaver(_ item: NSMenuItem) { screensaver.minutes = item.tag }
    // From the menu: wait a moment so closing the menu doesn't count as input.
    @objc private func showScreensaver() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.screensaver.show() } }
    @objc private func openPermissions() { Permissions.request(); Permissions.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    /// The Blue View logo's two ovals, as a menu bar template image.
    private static func logo() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.5, y: 9.5, width: 9.5, height: 6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 2.5, width: 9.5, height: 6)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
