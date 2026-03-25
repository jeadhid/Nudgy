// NudgePanelController.swift
// Nudgy v2.0 — macOS AppKit Bridge for the Liquid Glass NSPanel
// Compile only on macOS targets.

#if os(macOS)
import AppKit
import SwiftUI

// MARK: - NudgePanelController (Singleton)

/// Manages the lifecycle of a floating, non-activating NSPanel that displays
/// incoming nudges as a "Liquid Glass" overlay. Thread-safe via MainActor.
@MainActor
final class NudgePanelController {

    static let shared = NudgePanelController()
    private init() {}

    private var panel: NudgePanel?
    private var dismissTimer: Timer?

    // MARK: Public API

    func show(nudge: NudgeData) {
        // Cancel any in-progress dismiss
        dismissTimer?.invalidate()
        dismissTimer = nil

        // Tear down an old panel if still on screen
        if let existing = panel {
            existing.orderOut(nil)
            panel = nil
        }

        // Build and show new panel
        let newPanel = NudgePanel(nudge: nudge)
        newPanel.center()
        newPanel.makeKeyAndOrderFront(nil)          // orderFront won't steal focus (see NudgePanel)
        panel = newPanel

        // Fade in over 0.5 s
        newPanel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            newPanel.animator().alphaValue = 1
        }

        // Hold for 4 s, then fade out over 1 s
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fadeOut() }
        }
    }

    // MARK: Private

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            self.panel = nil
        })
    }
}

// MARK: - NudgePanel (NSPanel subclass)

/// A borderless, non-activating floating panel that renders the Liquid Glass nudge UI.
final class NudgePanel: NSPanel {

    init(nudge: NudgeData) {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 320, height: 320),
            styleMask: [
                .borderless,
                .nonactivatingPanel      // ← Does NOT steal focus from other apps
            ],
            backing: .buffered,
            defer: false
        )

        // Window flags
        isOpaque            = false
        hasShadow           = true
        backgroundColor     = .clear
        level               = .floating             // Floats above normal windows
        collectionBehavior  = [.canJoinAllSpaces,   // Appears on all Spaces
                               .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true

        // Embed SwiftUI content
        let nudgeView = NudgePanelContentView(nudge: nudge)
        let host = NSHostingView(rootView: nudgeView)
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView = host
    }

    /// Non-activating: returning false keeps focus in the current app.
    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - NudgePanelContentView (SwiftUI inside NSPanel)

/// The "Liquid Glass" visual — rendered inside the NSPanel via NSHostingView.
struct NudgePanelContentView: View {
    let nudge: NudgeData

    var body: some View {
        ZStack {
            // Frosted glass background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            // Glass edge
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )

            // Content
            VStack(spacing: 18) {
                Text(nudge.emoji)
                    .font(.system(size: 90))

                VStack(spacing: 5) {
                    Text(nudge.senderName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("sent you a nudge")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(36)
        }
        .frame(width: 300, height: 300)
        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 12)
    }
}

// MARK: - NSVisualEffectView Bridge

/// Wraps NSVisualEffectView for use inside SwiftUI.
struct VisualEffectView: NSViewRepresentable {
    var material:     NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = .active
        v.wantsLayer   = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material     = material
        nsView.blendingMode = blendingMode
    }
}

#endif  // os(macOS)
