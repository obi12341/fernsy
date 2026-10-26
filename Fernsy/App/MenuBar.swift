import FernsyPlayer
import SwiftUI

/// Menu bar item: Fernsy keeps running there (for recordings) when all windows are closed.
struct MenuBarContent: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let running = recorder.recordings.filter { $0.status == .recording }
        let next = recorder.recordings.filter { $0.status == .scheduled }.min { $0.start < $1.start }

        if running.isEmpty && next == nil {
            Text("No recordings scheduled")
        }
        ForEach(running) { recording in
            Menu("● \(recording.title) – \(recording.channelName)") {
                Text("Until \(recording.recordEnd.formatted(date: .omitted, time: .shortened))")
                Button("Stop Recording") { recorder.stop(recording.id) }
            }
        }
        if let next {
            Text("Next: \(next.title) – \(Self.when(next.start))")
        }
        Divider()
        Button("Open Fernsy") { MenuBarSupport.showLibrary(openWindow) }
        Button("Show Recordings") {
            app.requestedSection = .recordings
            MenuBarSupport.showLibrary(openWindow)
        }
        Divider()
        if !running.isEmpty {
            Text("Quitting Fernsy stops the running recording")
        }
        Button("Quit Fernsy") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return time }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " " + time
    }
}

struct MenuBarLabel: View {
    @ObservedObject var recorder: Recorder
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let recording = recorder.recordings.contains { $0.status == .recording }
        Image(nsImage: Self.symbol(recording: recording))
            .accessibilityLabel(recording ? Text("Fernsy – recording") : Text(verbatim: "Fernsy"))
            // The label lives as long as the menu bar item, also with every window closed: its
            // openWindow still works when the library's has gone with its window.
            .onAppear { PlayerWindow.menuBarOpenWindow = openWindow }
    }

    /// The TV symbol in the menu bar's text colour, with a red dot while recording. Not a
    /// template image, so the dot stays red; the colour resolves when the image is drawn.
    static func symbol(recording: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular).applying(.preferringMonochrome())
        guard let tv = NSImage(systemSymbolName: "tv", accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            return NSImage()
        }
        guard recording else {
            tv.isTemplate = true
            return tv
        }
        let size = NSSize(width: tv.size.width + 3, height: max(tv.size.height, 16))
        let image = NSImage(size: size, flipped: false) { rect in
            // Drawn into a bitmap of its own, so tinting and the gap leave the menu bar alone.
            let scale = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 2
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * scale), pixelsHigh: Int(rect.height * scale),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
            rep.size = rect.size
            let color = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .black
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            tv.draw(in: NSRect(origin: NSPoint(x: 0, y: (rect.height - tv.size.height) / 2), size: tv.size))
            color.set()
            rect.fill(using: .sourceAtop)
            // A gap around the dot so it reads against the symbol.
            let dot = NSRect(x: rect.maxX - 7, y: 0.5, width: 6.5, height: 6.5)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSGraphicsContext.restoreGraphicsState()
            return rep.draw(in: rect)
        }
        image.isTemplate = false
        return image
    }
}

/// Dock icon only while a window is open; without windows Fernsy lives in the menu bar.
@MainActor
enum MenuBarSupport {
    static let enabledKey = "menuBar.enabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Real windows (library, player, settings), not the menu bar's own panel.
    private static var openWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.canBecomeMain && $0.styleMask.contains(.titled) }
    }

    static func windowWillClose(_ closing: NSWindow) {
        guard isEnabled, closing.canBecomeMain else { return }
        // After the close has gone through.
        DispatchQueue.main.async {
            if openWindows.filter({ $0 !== closing }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    static func windowDidOpen(_ window: NSWindow) {
        guard !isStartingWithoutWindow, window.canBecomeMain, NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        AppActivation.activate()
    }

    /// Brings the library window back, or opens a new one when it was closed.
    static func showLibrary(_ openWindow: OpenWindowAction) {
        startWithoutWindowUntil = nil
        NSApp.setActivationPolicy(.regular)
        AppActivation.activate()
        if let hidden = LibraryWindows.takeHidden() {
            hidden.makeKeyAndOrderFront(nil)
        } else if let existing = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix("library") == true && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
        }) {
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "library")
        }
    }

    // MARK: Opened at login

    private static var startWithoutWindowUntil: Date?
    private static var isStartingWithoutWindow: Bool { startWithoutWindowUntil.map { Date() < $0 } ?? false }

    /// Opened at login: closes the library window SwiftUI opens at launch, also when it appears a
    /// moment later. With the menu bar item Fernsy then runs there without a Dock icon.
    static func startWithoutWindow() {
        startWithoutWindowUntil = Date().addingTimeInterval(3)
        if isEnabled { NSApp.setActivationPolicy(.accessory) }
        for delay in [0, 0.1, 0.3, 0.6, 1, 2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard isStartingWithoutWindow else { return }
                for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("library") == true && window.isVisible {
                    window.close()
                }
            }
        }
    }
}
