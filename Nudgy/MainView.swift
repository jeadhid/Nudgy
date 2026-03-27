// MainView.swift
// Nudgy v2.0 — Shared SwiftUI Interface (macOS + iOS)

import SwiftUI

// MARK: - Root App Entry & Environment Wiring

/// Top-level view that wires the MultipeerManager into the environment.
/// Place this at the top of your @main App body.
struct NudgyRootView: View {
    @AppStorage("nickname") private var nickname: String = ""
    @AppStorage("favoriteEmoji") private var favoriteEmoji: String = "👋"

    @StateObject private var manager: MultipeerManager = {
        let stored = UserDefaults.standard.string(forKey: "nickname") ?? ""
        return MultipeerManager(nickname: stored.isEmpty ? "Me" : stored)
    }()

    var body: some View {
        MainView()
            .environmentObject(manager)
            .onChange(of: nickname) { _, newValue in
                manager.nickname = newValue.isEmpty ? "Me" : newValue
            }
    }
}

// MARK: - MainView

struct MainView: View {
    @EnvironmentObject var manager: MultipeerManager

    @AppStorage("nickname") private var nickname: String = ""
    @AppStorage("favoriteEmoji") private var favoriteEmoji: String = "👋"

    @State private var isEditingProfile = false
    @State private var showSpamAlert    = false

    // iOS nudge overlay
    @State private var nudgeOverlayData: NudgeData? = nil
    @State private var nudgeOverlayOpacity: Double  = 0

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                profileCard
                sectionDivider
                peerList
            }

            // iOS Liquid Glass overlay — rendered conditionally
            #if os(iOS)
            if let nudge = nudgeOverlayData {
                iOSNudgeOverlay(nudge: nudge)
                    .opacity(nudgeOverlayOpacity)
                    .transition(.opacity)
                    .zIndex(100)
            }
            #endif
        }
        // Spam alert toast
        .overlay(alignment: .top) {
            if manager.isSpamBlocked {
                spamToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: manager.isSpamBlocked)
                    .padding(.top, 12)
            }
        }
        // Nudge received handler
        .onChange(of: manager.receivedNudge) { _, nudge in
            guard let nudge else { return }
            handleReceivedNudge(nudge)
        }
        .sheet(isPresented: $isEditingProfile) {
            ProfileEditorView(nickname: $nickname, favoriteEmoji: $favoriteEmoji)
        }
    }

    // MARK: Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.08, blue: 0.12),
                Color(red: 0.12, green: 0.10, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Profile Card

    private var profileCard: some View {
        Button(action: { isEditingProfile = true }) {
            HStack(spacing: 16) {
                // Avatar bubble
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                    Text(favoriteEmoji)
                        .font(.system(size: 28))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("MY PROFILE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(1.5)
                    Text(nickname.isEmpty ? "Tap to set name" : nickname)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: Divider

    private var sectionDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            Text("NEARBY")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(2)
                .fixedSize()

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // MARK: Peer List

    private var peerList: some View {
        List {
            if manager.discoveredPeers.isEmpty {
                emptyStateRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(manager.discoveredPeers) { peer in
                    PeerRow(
                        peer: peer,
                        emoji: favoriteEmoji,
                        senderName: nickname.isEmpty ? "Me" : nickname
                    )
                    .environmentObject(manager)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                            .padding(.vertical, 3)
                    )
                    .listRowSeparator(.hidden)
                }
            }
        }
        .padding(.horizontal, 20)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            try? await Task.sleep(nanoseconds: 300_000_000)  // visual pause
            manager.refresh()
        }
    }

    private var emptyStateRow: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.25))
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("Scanning for nearby devices…")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: Spam Toast

    private var spamToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            Text("Slow down! Max 3 nudges per minute.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5))
        }
    }

    // MARK: Nudge Handling

    private func handleReceivedNudge(_ nudge: NudgeData) {
        #if os(macOS)
        NudgePanelController.shared.show(nudge: nudge)
        #else
        nudgeOverlayData    = nudge
        nudgeOverlayOpacity = 0
        withAnimation(.easeIn(duration: 0.5)) { nudgeOverlayOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeOut(duration: 1.0)) { nudgeOverlayOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                nudgeOverlayData = nil
            }
        }
        #endif

        // Clear so we can receive the same nudge again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            manager.receivedNudge = nil
        }
    }
}

// MARK: - Peer Row

struct PeerRow: View {
    @EnvironmentObject var manager: MultipeerManager
    let peer: DiscoveredPeer
    let emoji: String
    let senderName: String

    @State private var isBouncing = false

    var body: some View {
        Button(action: sendNudge) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 44, height: 44)
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Tap to send \(emoji)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                Text(emoji)
                    .font(.system(size: 26))
                    .scaleEffect(isBouncing ? 1.4 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.4), value: isBouncing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func sendNudge() {
        guard manager.canSend(to: peer) else { return }
        manager.send(emoji: emoji, senderName: senderName, to: peer)
        isBouncing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isBouncing = false }
    }
}

// MARK: - iOS Liquid Glass Overlay

#if os(iOS)
struct iOSNudgeOverlay: View {
    let nudge: NudgeData

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text(nudge.emoji)
                    .font(.system(size: 100))

                VStack(spacing: 6) {
                    Text(nudge.senderName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("sent you a nudge")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(48)
            .background {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                    )
            }
            .padding(40)
        }
        .allowsHitTesting(false)   // Non-interactive passthrough
    }
}
#endif

// MARK: - Profile Editor Sheet

struct ProfileEditorView: View {
    @Binding var nickname: String
    @Binding var favoriteEmoji: String
    @Environment(\.dismiss) private var dismiss

    private let emojiOptions = ["👋","🔥","💫","🎉","❤️","🚀","👾","🌊","⚡️","🦋","🍀","🎸"]

    @State private var draftName:  String = ""
    @State private var draftEmoji: String = "👋"

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Name") {
                    TextField("", text: $draftName)
                }
                Section("Favorite Emoji") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiOptions, id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 48, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(draftEmoji == emoji
                                              ? Color.accentColor.opacity(0.25)
                                              : Color.clear)
                                )
                                .onTapGesture { draftEmoji = emoji }
                        }
                    }
                    .padding(.top, 6)
                }
                #if os(iOS)
                VStack(spacing: 8) {
                    Text("Or type any emoji:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("", text: $draftEmoji)
                        .font(.system(size: 30))
                        .textFieldStyle(.plain)
                        .frame(width: 48, height: 48)
                        .multilineTextAlignment(.center)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(!emojiOptions.contains(draftEmoji) && !draftEmoji.isEmpty
                                      ? Color.accentColor.opacity(0.25)
                                      : Color.white.opacity(0.05))
                        )
                        .onChange(of: draftEmoji) { _, newValue in
                            if newValue.count > 1 {
                                draftEmoji = String(newValue.suffix(1))
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
                #endif
            }
            .padding(20)
            .navigationTitle("Edit Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        nickname      = draftName
                        favoriteEmoji = draftEmoji
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #if os(macOS)
            VStack(spacing: 8) {
                Text("Or type any emoji:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("", text: $draftEmoji)
                    .font(.system(size: 30))
                    .textFieldStyle(.plain)
                    .frame(width: 48, height: 48)
                    .multilineTextAlignment(.center)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(!emojiOptions.contains(draftEmoji) && !draftEmoji.isEmpty
                                  ? Color.accentColor.opacity(0.25)
                                  : Color.white.opacity(0.05))
                    )
                    .onChange(of: draftEmoji) { _, newValue in
                        if newValue.count > 1 {
                            draftEmoji = String(newValue.suffix(1))
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
            #endif
        }
        .onAppear {
            draftName  = nickname
            draftEmoji = favoriteEmoji
        }
    }
}


