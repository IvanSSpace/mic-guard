import SwiftUI
import AppKit
import Combine

/// SwiftUI's `MenuBarExtra` always forces its label into template (monochrome)
/// rendering — no combination of colors/backgrounds survives it. A real coloured
/// badge (like third-party apps show) needs a raw `NSStatusItem` with
/// `isTemplate = false`, so the icon is built here via AppKit instead.
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellable: AnyCancellable?

    override init() {
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MicGuardPanel())

        updateIcon()
        cancellable = LockState.shared.$isLocked.sink { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
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
