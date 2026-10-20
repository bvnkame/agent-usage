import SwiftUI
import AppKit
import Combine

/// Borderless panel that can become key (needed for text fields / buttons) without a title bar.
final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var item: NSStatusItem!
    var panel: Panel!
    var bag = Set<AnyCancellable>()
    var monitor: Any?
    var hideTimer: Timer?
    var hoverTimer: Timer?
    var pinned = false          // opened by click: stays until clicked away
    var lastRefresh = Date.distantPast

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self; item.button?.action = #selector(toggle)

        let host = NSHostingView(rootView: ContentView().environmentObject(store))
        host.wantsLayer = true
        host.layer?.cornerRadius = 14; host.layer?.masksToBounds = true
        panel = Panel(contentRect: NSRect(origin: .zero, size: popupSize), styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: true)
        panel.contentView = host
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in DispatchQueue.main.async { self?.updateTitle() } }.store(in: &bag)
        updateTitle()
        startHoverWatch()
    }

    func updateTitle() {
        guard let b = item.button else { return }
        b.image = store.barImage
        b.imagePosition = .imageOnly
        b.attributedTitle = NSAttributedString(string: "")
    }

    /// Place the panel right under the status item, clamped inside the screen's visible area.
    func position() {
        guard let bw = item.button?.window else { return }
        let screen = bw.screen ?? NSScreen.main!
        let vis = screen.visibleFrame, bf = bw.frame
        let size = NSSize(width: min(popupSize.width, vis.width - 16), height: min(popupSize.height, vis.height - 8))
        var x = bf.midX - size.width / 2
        x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8)
        let y = vis.maxY - size.height - 4          // vis.maxY is the bottom edge of the menu bar
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // Hover: poll the global mouse position (tracking areas on status-bar buttons are unreliable).
    // Entering the icon opens the popup; leaving both icon and popup closes it after a short grace period.
    var outSince: Date?
    func startHoverWatch() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hoverTick() }
        }
    }
    func hoverTick() {
        guard let bw = item.button?.window else { return }
        let loc = NSEvent.mouseLocation
        let inIcon = bw.frame.insetBy(dx: -2, dy: -2).contains(loc)
        let inPanel = panel.isVisible && panel.frame.insetBy(dx: -6, dy: -6).contains(loc)
        if inIcon || inPanel { outSince = nil }
        if inIcon && !panel.isVisible { show(activate: false); return }
        if panel.isVisible && !pinned && !inIcon && !inPanel {
            if outSince == nil { outSince = Date() }
            else if Date().timeIntervalSince(outSince!) > 0.35 { hide() }
        }
    }

    @objc func toggle() {
        if panel.isVisible && pinned { hide() }
        else { pinned = true; hideTimer?.invalidate(); show(activate: true) }   // click pins the popup open
    }

    func show(activate: Bool) {
        position()
        if activate { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else { panel.orderFrontRegardless() }
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
        if Date().timeIntervalSince(lastRefresh) > 10 { lastRefresh = Date(); Task { await store.refresh() } }
    }
    func hide() {
        hideTimer?.invalidate(); pinned = false
        panel.orderOut(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
