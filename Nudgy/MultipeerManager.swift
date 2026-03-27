// MultipeerManager.swift
// Nudgy v2.0 — Shared Connectivity Layer

import Foundation
import Combine
import MultipeerConnectivity

#if os(macOS)
import AppKit
#else

import UIKit
#endif

// MARK: - Data Model

struct NudgeData: Codable, Equatable {
    let senderName: String
    let emoji: String
}

// MARK: - Peer Model

struct DiscoveredPeer: Identifiable, Equatable {
    let id: MCPeerID
    var displayName: String { id.displayName }
    static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool { lhs.id == rhs.id }
}

// MARK: - Anti-Spam Tracker

private struct SpamKey: Hashable {
    let localPeer: String
    let remotePeer: String
}

private class SpamTracker {
    private var log: [SpamKey: [Date]] = [:]
    private let limit = 10
    private let window: TimeInterval = 60

    func canSend(from local: String, to remote: String) -> Bool {
        let key = SpamKey(localPeer: local, remotePeer: remote)
        let now = Date()
        return (log[key] ?? []).filter { now.timeIntervalSince($0) < window }.count < limit
    }

    func record(from local: String, to remote: String) {
        let key = SpamKey(localPeer: local, remotePeer: remote)
        let now = Date()
        var recent = (log[key] ?? []).filter { now.timeIntervalSince($0) < window }
        recent.append(now)
        log[key] = recent
    }

    func reset() { log.removeAll() }
}

// MARK: - MultipeerManager

final class MultipeerManager: NSObject, ObservableObject {

    // MARK: Published

    @Published var discoveredPeers: [DiscoveredPeer] = []
    @Published var receivedNudge: NudgeData? = nil
    @Published var isSpamBlocked: Bool = false
    @Published var lastBlockedPeer: String? = nil

    // Diagnostic log — shown in DebugView
    @Published var log: [String] = []

    // MARK: Private

    // ✅ Short, hyphen-free, ≤15 chars — universally accepted by MPC
    static let serviceType = "nudgep2p"

    private var myPeerID:   MCPeerID
    private var session:    MCSession
    private var browser:    MCNearbyServiceBrowser
    private var advertiser: MCNearbyServiceAdvertiser
    private let spamTracker = SpamTracker()
    private var pendingInvites: Set<MCPeerID> = []

    var nickname: String {
        didSet { restart(withNickname: nickname) }
    }

    // MARK: Init

    init(nickname: String) {
        self.nickname = nickname
        let peerID = MultipeerManager.makePeerID(nickname: nickname)
        let svc    = MultipeerManager.serviceType
        self.myPeerID   = peerID
        self.session    = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.browser    = MCNearbyServiceBrowser(peer: peerID, serviceType: svc)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: svc)
        super.init()
        assignDelegates()
        // Defer one tick so the app's network permission prompt can resolve first
        DispatchQueue.main.async { self.start() }
    }

    // MARK: Helpers

    private static func makePeerID(nickname: String) -> MCPeerID {
        #if os(macOS)
        let deviceName = Host.current().localizedName ?? "Mac"
        #else
        let deviceName = UIDevice.current.name
        #endif
        let display = nickname.isEmpty ? deviceName : nickname
        return MCPeerID(displayName: String(display.prefix(63)))
    }

    private func assignDelegates() {
        session.delegate    = self
        browser.delegate    = self
        advertiser.delegate = self
    }

    private func start() {
        nudgeLog("▶ start() — peer='\(myPeerID.displayName)' svc='\(MultipeerManager.serviceType)'")
        browser.startBrowsingForPeers()
        advertiser.startAdvertisingPeer()
        nudgeLog("✅ browser + advertiser started")
    }

    private func stop() {
        nudgeLog("⏹ stop()")
        browser.stopBrowsingForPeers()
        advertiser.stopAdvertisingPeer()
        session.disconnect()
        pendingInvites.removeAll()
    }

    func nudgeLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)"
        print("[Nudgy] \(line)")
        DispatchQueue.main.async {
            self.log.insert(line, at: 0)
            if self.log.count > 60 { self.log.removeLast() }
        }
    }

    // MARK: Public API

    func refresh() {
        nudgeLog("🔄 refresh()")
        stop()
        DispatchQueue.main.async { self.discoveredPeers.removeAll() }
        spamTracker.reset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.rebuild(nickname: self.nickname)
            self.start()
        }
    }

    private func restart(withNickname name: String) {
        nudgeLog("🔁 restart — new nickname='\(name)'")
        stop()
        DispatchQueue.main.async { self.discoveredPeers.removeAll() }
        rebuild(nickname: name)
        DispatchQueue.main.async { self.start() }
    }

    private func rebuild(nickname name: String) {
        let peerID = MultipeerManager.makePeerID(nickname: name)
        let svc    = MultipeerManager.serviceType
        myPeerID   = peerID
        session    = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        browser    = MCNearbyServiceBrowser(peer: peerID, serviceType: svc)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: svc)
        assignDelegates()
        nudgeLog("🔨 rebuilt — peer='\(peerID.displayName)'")
    }

    // MARK: Send

    func send(emoji: String, senderName: String, to peer: DiscoveredPeer) {
        guard canSend(to: peer) else { return }
        let nudge = NudgeData(senderName: senderName, emoji: emoji)
        guard let data = try? JSONEncoder().encode(nudge) else { return }
        spamTracker.record(from: myPeerID.displayName, to: peer.displayName)
        nudgeLog("📤 sending '\(emoji)' to '\(peer.displayName)' — connected=\(session.connectedPeers.contains(peer.id))")

        if session.connectedPeers.contains(peer.id) {
            // Already connected — send immediately
            sendData(data, to: peer.id)
        } else {
            // Not connected — invite (clearing any stale pending flag first so
            // a re-tap after a disconnect always triggers a fresh invite)
            pendingInvites.remove(peer.id)
            pendingInvites.insert(peer.id)
            browser.invitePeer(peer.id, to: session, withContext: nil, timeout: 10)
            nudgeLog("📨 invited '\(peer.displayName)' — waiting for connection")
            attemptSend(data: data, to: peer.id, retryCount: 6)
        }
    }

    private func sendData(_ data: Data, to peerID: MCPeerID) {
        do {
            try session.send(data, toPeers: [peerID], with: .reliable)
            nudgeLog("✅ sent to '\(peerID.displayName)'")
        } catch {
            nudgeLog("❌ send error: \(error.localizedDescription)")
        }
    }

    private func attemptSend(data: Data, to peerID: MCPeerID, retryCount: Int) {
        if session.connectedPeers.contains(peerID) {
            sendData(data, to: peerID)
        } else if retryCount > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.attemptSend(data: data, to: peerID, retryCount: retryCount - 1)
            }
        } else {
            nudgeLog("⚠️ gave up sending to '\(peerID.displayName)' after retries")
        }
    }

    func canSend(to peer: DiscoveredPeer) -> Bool {
        let allowed = spamTracker.canSend(from: myPeerID.displayName, to: peer.displayName)
        if !allowed {
            nudgeLog("🚫 spam blocked — too many nudges to '\(peer.displayName)'")
            DispatchQueue.main.async {
                self.isSpamBlocked   = true
                self.lastBlockedPeer = peer.displayName
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isSpamBlocked   = false
                self.lastBlockedPeer = nil
            }
        }
        return allowed
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let label: String
        switch state {
        case .connected:    label = "🟢 connected"
        case .connecting:   label = "🟡 connecting"
        case .notConnected: label = "🔴 disconnected"
        @unknown default:   label = "❓ unknown"
        }
        nudgeLog("SESSION \(label) — '\(peerID.displayName)'")

        // ── Do NOT remove the peer from discoveredPeers here ─────────────────
        // Session state and Bonjour discovery are independent. A session can
        // disconnect (timeout, handshake conflict, network blip) while the
        // device is still visible on the local network. Removing the peer from
        // the list here causes the "it appears then immediately vanishes" bug.
        // Peers are only removed in lostPeer() when Bonjour stops seeing them.
        // ─────────────────────────────────────────────────────────────────────
        if state != .connecting {
            DispatchQueue.main.async { self.pendingInvites.remove(peerID) }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let nudge = try? JSONDecoder().decode(NudgeData.self, from: data) else {
            nudgeLog("⚠️ received undecodable data from '\(peerID.displayName)'")
            return
        }
        nudgeLog("📩 received '\(nudge.emoji)' from '\(nudge.senderName)'")
        DispatchQueue.main.async { self.receivedNudge = nudge }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.receivedNudge = nil }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        // Prevent discovering ourselves (or old phantom peers from before a refresh)
        guard peerID.displayName != myPeerID.displayName else { return }

        nudgeLog("👀 found peer '\(peerID.displayName)'")
        let peer = DiscoveredPeer(id: peerID)
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peer) {
                self.discoveredPeers.append(peer)
            }
        }
        // ── Do NOT auto-invite here ──────────────────────────────────────────
        // Both devices run browser + advertiser simultaneously. If both sides
        // auto-invite on foundPeer, they each accept the other's invite and two
        // competing sessions form — one wins, one immediately disconnects, and
        // the peer vanishes from the UI. Instead: invite only when the user
        // actually taps to send (in send()), and accept all incoming invites
        // via the advertiser delegate. Only one side ends up as initiator.
        // ─────────────────────────────────────────────────────────────────────
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        nudgeLog("💨 lost peer '\(peerID.displayName)'")
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0.id == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        nudgeLog("❌ BROWSER FAILED: \(error.localizedDescription) — code \((error as NSError).code)")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nudgeLog("🤝 received invitation from '\(peerID.displayName)' — auto-accepting")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        nudgeLog("❌ ADVERTISER FAILED: \(error.localizedDescription) — code \((error as NSError).code)")
    }
}

