// DebugView.swift
// Nudgy — Temporary Diagnostic View
// Add this to your project, then put DebugView() anywhere in your app to see live MPC logs.
// DELETE this file once discovery is working.

import SwiftUI

struct DebugView: View {
    @EnvironmentObject var manager: MultipeerManager

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {

                // ── Status bar ──────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("My PeerID", systemImage: "person.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(MultipeerManager.serviceType)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                    }

                    // Peers
                    HStack(spacing: 6) {
                        Circle()
                            .fill(manager.discoveredPeers.isEmpty ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        Text(manager.discoveredPeers.isEmpty
                             ? "No peers found yet"
                             : "\(manager.discoveredPeers.count) peer(s): " +
                               manager.discoveredPeers.map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                    }
                }
            #if os(iOS)
                .background(Color(uiColor: .systemGroupedBackground))
            #else
                .background(.background)
            #endif

                Divider()

                // ── Log list ────────────────────────────────────────────
                if manager.log.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Waiting for MPC events…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(manager.log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(color(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 2)
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                Divider()

                // ── Controls ────────────────────────────────────────────
                HStack {
                    Button("Refresh") { manager.refresh() }
                        .buttonStyle(.borderedProminent)
                    Button("Clear Log") {
                        manager.log.removeAll()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("\(manager.log.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Nudgy Diagnostics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private func color(for line: String) -> Color {
        if line.contains("❌") { return .red }
        if line.contains("⚠️") { return .orange }
        if line.contains("✅") || line.contains("🟢") { return .green }
        if line.contains("👀") || line.contains("📩") { return .blue }
        if line.contains("🔴") { return .red.opacity(0.7) }
        return .primary
    }
}

