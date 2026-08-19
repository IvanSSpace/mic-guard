import SwiftUI
import AppKit
import Combine

/// SwiftUI's `MenuBarExtra` always forces its label into template (monochrome)
/// rendering — no combination of colors/backgrounds survives it. A real coloured
/// badge (like third-party apps show) needs a raw `NSStatusItem` with
/// `isTemplate = false`, so the icon is built here via AppKit instead.
///
/// The dropdown itself is a plain borderless panel, not `NSPopover` — NSPopover
/// always draws its arrow/tail pointing at the button, with no public switch to
/// turn it off. A `.nonactivatingPanel` gives the same simple rectangle other
/// menu bar apps show, positioned manually under the status item.
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var cancellable: AnyCancellable?
    private var outsideClickMonitor: Any?

    override init() {
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleContent)

        let hosting = NSHostingView(rootView: MicGuardPanel())
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.contentView = hosting

        updateIcon()
        cancellable = LockState.shared.$isLocked.sink { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    @objc private func toggleContent() {
        if panel.isVisible {
            closeContent()
        } else {
            showContent()
        }
    }

    private func showContent() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let origin = NSPoint(
            x: buttonFrame.midX - size.width / 2,
            y: buttonFrame.minY - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeContent()
        }
    }

    private func closeContent() {
        panel.orderOut(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func updateIcon() {
        let renderer = ImageRenderer(content: BadgeIcon(locked: LockState.shared.isLocked))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        image.isTemplate = false
        statusItem.button?.image = image
    }
}

private struct BadgeIcon: View {
    let locked: Bool

    var body: some View {
        Image(systemName: locked ? "mic.slash.fill" : "mic.fill")
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 24, height: 20)
    }
}
