// NudgyApp.swift
// Nudgy v2.0 — App Entry Point (macOS + iOS)
// Place this file in your shared app target.

import SwiftUI

@main
struct NudgyApp: App {

    var body: some Scene {
        #if os(macOS)
        Window("Nudgy", id: "main") {
            NudgyRootView()
                .frame(minWidth: 360, idealWidth: 400, maxWidth: 500,
                       minHeight: 500, idealHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 620)
        #else
        WindowGroup {
            NudgyRootView()
                .preferredColorScheme(.dark)
        }
        #endif
    }
}
