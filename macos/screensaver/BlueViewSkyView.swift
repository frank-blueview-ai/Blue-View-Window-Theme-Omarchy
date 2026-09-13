// Blue View OS for macOS: the live sky screensaver.
//
// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
//
// The Blue View sky (Resources/sky, the same page as the Omarchy and Windows
// versions) with the logo, clock and 7-day forecast, in a WKWebView.
//
// macOS 14 and later host screensavers in legacyScreenSaver, which needs a few
// workarounds, as in Aerial and ScreenSaverMinimal:
//   - stopAnimation isn't called when the screensaver ends; tear down on the
//     com.apple.screensaver.willstop notification and exit shortly after, or
//     instances keep running in the background.
//   - The host's views make WebKit think the page is hidden, which pauses
//     animation; turn off occlusion detection and report the page as visible.
//   - On macOS 26, System Settings creates a zero-size "ghost" instance, and
//     isPreview isn't reliable.

import ScreenSaver
import WebKit

@objc(BlueViewSkyView)
final class BlueViewSkyView: ScreenSaverView {
    private var webView: WKWebView?
    private var ghost = false
    private static var exitScheduled = false

    override init?(frame: NSRect, isPreview: Bool) {
        var preview = isPreview || (frame.width < 400 && frame.height < 300)
        var ghost = false
        if #available(macOS 26, *) {
            ghost = isPreview && frame == .zero
            preview = !Self.screenLocked() && frame.width < 800
        }
        super.init(frame: frame, isPreview: preview)
        self.ghost = ghost
        animationTimeInterval = 1.0 // WebKit animates the page itself
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        if ghost { return }

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(willStop(_:)),
                                                            name: Notification.Name("com.apple.screensaver.willstop"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep(_:)),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func startAnimation() {
        super.startAnimation()
        guard !ghost, webView == nil else { return }

        let configuration = WKWebViewConfiguration()
        if #available(macOS 14, *) {
            configuration.preferences.inactiveSchedulingPolicy = .none
        }
        // The preview thumbnail is tiny: the bare sky, gently. Full screen: logo, clock and forecast.
        let query = isPreview ? "fps=12" : "overlay=1&fps=30"
        let script = """
        Object.defineProperty(Document.prototype, 'hidden', { configurable: true, get: () => false });
        Object.defineProperty(Document.prototype, 'visibilityState', { configurable: true, get: () => 'visible' });
        window.BVOS_QUERY = '\(query)';
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let web = WKWebView(frame: targetFrame(), configuration: configuration)
        let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if web.responds(to: occlusion) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(web.method(for: occlusion), to: Setter.self)(web, occlusion, false)
        }
        addSubview(web)
        webView = web

        // Bundle(for:) is this screensaver; Bundle.main is the system host.
        if let page = Bundle(for: Self.self).url(forResource: "index", withExtension: "html", subdirectory: "sky") {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        teardown()
    }

    override func animateOneFrame() {}

    override func layout() {
        super.layout()
        webView?.frame = targetFrame()
    }

    // Keep clicks from reaching the web page.
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    // Bounds can arrive as zero or in backing pixels; fit the screen.
    private func targetFrame() -> NSRect {
        guard !isPreview, let screen = (window?.screen ?? NSScreen.main)?.frame.size else { return bounds }
        return NSRect(x: 0, y: 0,
                      width: bounds.width > 1 ? min(bounds.width, screen.width) : screen.width,
                      height: bounds.height > 1 ? min(bounds.height, screen.height) : screen.height)
    }

    private func teardown() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    @objc private func willStop(_ notification: Notification) {
        teardown()
        guard !isPreview, !Self.exitScheduled else { return }
        Self.exitScheduled = true
        // Exiting right away makes the host start the screensaver again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
    }

    @objc private func willSleep(_ notification: Notification) {
        if !isPreview { exit(0) }
    }

    private static func screenLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
