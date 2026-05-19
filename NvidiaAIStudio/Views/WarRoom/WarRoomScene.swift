import SpriteKit
import SwiftUI

// MARK: - Agent State

enum OfficeAgentState: Equatable {
    case idle
    case working
    case speaking
    case debating
    case waiting(for: String)  // blocked on another agent

    static func == (lhs: OfficeAgentState, rhs: OfficeAgentState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.working, .working), (.speaking, .speaking), (.debating, .debating): return true
        case (.waiting(let a), .waiting(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - AgentPodNode

/// A glassmorphic "workstation pod" that represents one agent on the office floor.
final class AgentPodNode: SKNode {

    // MARK: Visuals
    private let podBG: SKShapeNode
    private let accentGlow: SKShapeNode
    private let cropNode: SKCropNode
    private let avatarSprite: SKSpriteNode
    private let nameLabel: SKLabelNode
    private let roleLabel: SKLabelNode
    private let statusDot: SKShapeNode
    private let statusLabel: SKLabelNode
    private let terminalNode: SKShapeNode
    private let terminalText: SKLabelNode

    // MARK: Data
    let agentName: String
    let accentColor: SKColor
    var homePosition: CGPoint = .zero
    private(set) var state: OfficeAgentState = .idle

    // MARK: Terminal fake text (cycles to simulate activity)
    private let terminalLines = [
        "▶ Analysing requirements...",
        "▶ Compiling strategy matrix...",
        "▶ Processing token stream...",
        "▶ Evaluating trade-offs...",
        "▶ Synthesizing output..."
    ]
    private var terminalLineIndex = 0

    // MARK: Init
    init(name: String, role: String, accentHex: String) {
        self.agentName = name
        self.accentColor = SKColor(hex: accentHex) ?? .cyan

        // ── Pod background ──────────────────────────────────────────────
        let podW: CGFloat = 108, podH: CGFloat = 130
        podBG = SKShapeNode(rectOf: CGSize(width: podW, height: podH), cornerRadius: 14)
        podBG.fillColor = SKColor(white: 1, alpha: 0.04)
        podBG.strokeColor = SKColor(white: 1, alpha: 0.12)
        podBG.lineWidth = 1
        podBG.zPosition = 0

        // Accent glow ring (normally dim, pulses when working)
        accentGlow = SKShapeNode(rectOf: CGSize(width: podW + 4, height: podH + 4), cornerRadius: 15)
        accentGlow.fillColor = .clear
        accentGlow.strokeColor = .clear
        accentGlow.lineWidth = 2
        accentGlow.alpha = 0
        accentGlow.zPosition = -1

        // ── Avatar (circular crop) ──────────────────────────────────────
        let avatarD: CGFloat = 58
        let avatarName = "avatar_\(name.lowercased())"
        var texture: SKTexture
        if let url = Bundle.main.url(forResource: avatarName, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            texture = SKTexture(image: img)
        } else {
            // Coloured circle fallback
            let fallback = NSImage(size: NSSize(width: 128, height: 128))
            fallback.lockFocus()
            NSColor(hex: accentHex)?.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 128, height: 128)).fill()
            fallback.unlockFocus()
            texture = SKTexture(image: fallback)
        }

        avatarSprite = SKSpriteNode(texture: texture,
                                    size: CGSize(width: avatarD, height: avatarD))
        let maskCircle = SKShapeNode(circleOfRadius: avatarD / 2)
        maskCircle.fillColor = .white
        cropNode = SKCropNode()
        cropNode.maskNode = maskCircle
        cropNode.addChild(avatarSprite)
        cropNode.zPosition = 2

        // ── Labels ──────────────────────────────────────────────────────
        nameLabel = SKLabelNode(text: name)
        nameLabel.fontName = "SFProDisplay-Semibold"
        nameLabel.fontSize = 11
        nameLabel.fontColor = .white
        nameLabel.zPosition = 2

        roleLabel = SKLabelNode(text: role)
        roleLabel.fontName = "SFProText-Regular"
        roleLabel.fontSize = 8
        roleLabel.fontColor = SKColor(white: 1, alpha: 0.4)
        roleLabel.zPosition = 2

        // ── Status indicator ────────────────────────────────────────────
        statusDot = SKShapeNode(circleOfRadius: 4)
        statusDot.fillColor = SKColor(white: 1, alpha: 0.25)
        statusDot.strokeColor = .clear
        statusDot.zPosition = 3

        statusLabel = SKLabelNode(text: "Idle")
        statusLabel.fontName = "SFProText-Regular"
        statusLabel.fontSize = 8
        statusLabel.fontColor = SKColor(white: 1, alpha: 0.3)
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.zPosition = 3

        // ── Terminal window (hidden by default) ─────────────────────────
        terminalNode = SKShapeNode(rectOf: CGSize(width: 96, height: 22), cornerRadius: 4)
        terminalNode.fillColor = SKColor(red: 0, green: 0.1, blue: 0.05, alpha: 0.9)
        terminalNode.strokeColor = SKColor(red: 0, green: 0.8, blue: 0.4, alpha: 0.4)
        terminalNode.lineWidth = 1
        terminalNode.alpha = 0
        terminalNode.zPosition = 4

        terminalText = SKLabelNode(text: "")
        terminalText.fontName = "SFMono-Regular"
        terminalText.fontSize = 6.5
        terminalText.fontColor = SKColor(red: 0.2, green: 1, blue: 0.5, alpha: 0.85)
        terminalText.horizontalAlignmentMode = .left
        terminalText.zPosition = 5

        super.init()

        // Add children
        addChild(podBG)
        addChild(accentGlow)
        addChild(cropNode)
        addChild(nameLabel)
        addChild(roleLabel)
        addChild(statusDot)
        addChild(statusLabel)
        addChild(terminalNode)
        terminalNode.addChild(terminalText)

        layout()
        startIdleBreathe()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout (SpriteKit origin = bottom-left of node's frame)
    private func layout() {
        cropNode.position    = CGPoint(x: 0, y: 22)
        nameLabel.position   = CGPoint(x: 0, y: -10)
        roleLabel.position   = CGPoint(x: 0, y: -22)
        statusDot.position   = CGPoint(x: -26, y: -36)
        statusLabel.position = CGPoint(x: -18, y: -39)
        terminalNode.position = CGPoint(x: 0, y: -58)
        terminalText.position = CGPoint(x: -44, y: -3)
    }

    // MARK: Idle breathe
    private func startIdleBreathe() {
        let delay = Double.random(in: 0...1.5)
        let dur   = Double.random(in: 2.2...3.2)
        let breathe = SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.04, duration: dur),
                SKAction.scale(to: 0.96, duration: dur)
            ]))
        ])
        cropNode.run(breathe, withKey: "breathe")
    }

    // MARK: - State transitions

    func setState(_ newState: OfficeAgentState, animated: Bool = true) {
        guard newState != state else { return }
        state = newState

        cropNode.removeAction(forKey: "breathe")
        cropNode.removeAction(forKey: "bounce")
        removeAction(forKey: "glow_pulse")
        childNode(withName: "waiting_balloon")?.removeFromParent()

        switch newState {
        case .idle:
            setStatusAppearance(text: "Idle", dotColor: SKColor(white: 1, alpha: 0.25))
            accentGlow.run(SKAction.fadeOut(withDuration: 0.4))
            hideTerminal()
            cropNode.run(SKAction.scale(to: 1, duration: 0.3)) { [weak self] in
                self?.startIdleBreathe()
            }

        case .working:
            setStatusAppearance(text: "Working", dotColor: .green)
            showGlowPulse()
            showTerminal()
            cropNode.run(SKAction.scale(to: 1.08, duration: 0.3))

        case .speaking:
            setStatusAppearance(text: "Speaking…", dotColor: .cyan)
            showGlowPulse()
            let bounce = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 7, duration: 0.22),
                SKAction.moveBy(x: 0, y: -7, duration: 0.22)
            ]))
            cropNode.run(bounce, withKey: "bounce")

        case .debating:
            setStatusAppearance(text: "Debating", dotColor: .orange)
            showGlowPulse()
            cropNode.run(SKAction.scale(to: 1.05, duration: 0.3))

        case .waiting(let blockedOn):
            setStatusAppearance(text: "⏳ Waiting", dotColor: .yellow)
            accentGlow.strokeColor = SKColor.yellow.withAlphaComponent(0.4)
            accentGlow.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.8, duration: 1.2),
                SKAction.fadeAlpha(to: 0.2, duration: 1.2)
            ])), withKey: "glow_pulse")
            // show a small balloon above the pod
            showWaitingBalloon(text: "Wait: \(blockedOn)")
        }
    }

    private func showWaitingBalloon(text: String) {
        // Remove any existing balloon
        childNode(withName: "waiting_balloon")?.removeFromParent()

        let balloon = SKShapeNode(rectOf: CGSize(width: 100, height: 20), cornerRadius: 6)
        balloon.name = "waiting_balloon"
        balloon.fillColor = SKColor.yellow.withAlphaComponent(0.12)
        balloon.strokeColor = SKColor.yellow.withAlphaComponent(0.5)
        balloon.lineWidth = 1
        balloon.position = CGPoint(x: 0, y: 78)
        balloon.zPosition = 10

        let lbl = SKLabelNode(text: text)
        lbl.fontName = "SFProText-Regular"
        lbl.fontSize = 7
        lbl.fontColor = SKColor.yellow.withAlphaComponent(0.85)
        lbl.verticalAlignmentMode = .center
        balloon.addChild(lbl)

        let fade = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 1, duration: 0.8),
            SKAction.fadeAlpha(to: 0.4, duration: 0.8)
        ]))
        balloon.run(fade)
        addChild(balloon)
    }

    private func setStatusAppearance(text: String, dotColor: SKColor) {
        statusLabel.text = text
        statusLabel.fontColor = dotColor.withAlphaComponent(0.85)
        statusDot.fillColor = dotColor
    }

    private func showGlowPulse() {
        accentGlow.strokeColor = accentColor.withAlphaComponent(0.7)
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 1, duration: 0.7),
            SKAction.fadeAlpha(to: 0.3, duration: 0.7)
        ]))
        accentGlow.run(pulse, withKey: "glow_pulse")
    }

    private func showTerminal() {
        terminalNode.run(SKAction.fadeIn(withDuration: 0.4))
        scrollTerminal()
    }

    private func hideTerminal() {
        terminalNode.run(SKAction.fadeOut(withDuration: 0.3))
        terminalNode.removeAction(forKey: "terminal_scroll")
    }

    private func scrollTerminal() {
        let update = SKAction.run { [weak self] in
            guard let self else { return }
            self.terminalText.text = self.terminalLines[self.terminalLineIndex % self.terminalLines.count]
            self.terminalLineIndex += 1
        }
        let wait = SKAction.wait(forDuration: 1.8)
        terminalNode.run(SKAction.repeatForever(SKAction.sequence([update, wait])), withKey: "terminal_scroll")
        // Run first tick immediately
        terminalText.text = terminalLines[0]
    }
}

// MARK: - War Room Scene

/// The main SpriteKit scene representing the glassmorphic virtual office.
final class WarRoomScene: SKScene {

    // MARK: Agent registry
    private(set) var pods: [String: AgentPodNode] = [:]
    private var layoutCounter: Int = 0

    // MARK: Debate table
    private var debateTable: SKNode?
    private var isDebateActive = false
    private var currentDebateParticipants: [String] = []

    // MARK: Layout constants
    private let columns        = 4
    private let podSpacingX: CGFloat = 148
    private let podSpacingY: CGFloat = 155
    private let topPadding:  CGFloat = 110

    // MARK: - Setup ────────────────────────────────────────────────────

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        setupBackground()
    }

    private func setupBackground() {
        // ── Grid ──────────────────────────────────────────────────────
        let gridLayer = SKNode()
        gridLayer.zPosition = -9
        let step: CGFloat = 52
        let gc = SKColor.cyan.withAlphaComponent(0.035)

        var y: CGFloat = 0
        while y <= size.height + step {
            let l = SKShapeNode(rectOf: CGSize(width: size.width, height: 0.5))
            l.fillColor = gc; l.strokeColor = .clear
            l.position = CGPoint(x: size.width / 2, y: y)
            gridLayer.addChild(l); y += step
        }
        var x: CGFloat = 0
        while x <= size.width + step {
            let l = SKShapeNode(rectOf: CGSize(width: 0.5, height: size.height))
            l.fillColor = gc; l.strokeColor = .clear
            l.position = CGPoint(x: x, y: size.height / 2)
            gridLayer.addChild(l); x += step
        }
        addChild(gridLayer)

        // ── Corner accent glows ───────────────────────────────────────
        for (cx, cy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
            let g = SKShapeNode(ellipseOf: CGSize(width: 320, height: 320))
            g.fillColor = SKColor.cyan.withAlphaComponent(0.025)
            g.strokeColor = .clear
            g.position = CGPoint(x: size.width * cx, y: size.height * cy)
            g.zPosition = -8
            addChild(g)
        }

        // ── "NVIDIA AI STUDIO" watermark ──────────────────────────────
        let watermark = SKLabelNode(text: "NVIDIA AI STUDIO — COMMAND CENTER")
        watermark.fontName = "SFMono-Regular"
        watermark.fontSize = 9
        watermark.fontColor = SKColor.white.withAlphaComponent(0.06)
        watermark.position = CGPoint(x: size.width / 2, y: 14)
        watermark.zPosition = -7
        addChild(watermark)
    }

    // MARK: - Pod Grid Position ────────────────────────────────────────

    private func gridPosition(for index: Int) -> CGPoint {
        let col = index % columns
        let row = index / columns
        let totalWidth = CGFloat(columns - 1) * podSpacingX
        let startX = (size.width - totalWidth) / 2
        let startY = size.height - topPadding
        return CGPoint(x: startX + CGFloat(col) * podSpacingX,
                       y: startY - CGFloat(row) * podSpacingY)
    }

    // MARK: - Public API ───────────────────────────────────────────────

    /// Spawn a new agent pod. `index` determines grid slot.
    func spawnAgent(name: String, role: String, accentHex: String, index: Int) {
        guard pods[name] == nil else { return }

        let pod = AgentPodNode(name: name, role: role, accentHex: accentHex)
        let target = gridPosition(for: index)
        pod.homePosition = target
        pod.zPosition = 1

        // Drop-in animation from above
        pod.position = CGPoint(x: target.x, y: size.height + 80)
        pod.alpha = 0
        addChild(pod)
        pods[name] = pod

        let dropIn = SKAction.group([
            SKAction.moveTo(y: target.y, duration: 0.55),
            SKAction.fadeIn(withDuration: 0.45)
        ])
        dropIn.timingMode = .easeOut
        pod.run(SKAction.sequence([
            SKAction.wait(forDuration: Double(index) * 0.07),
            dropIn
        ]))
    }

    /// Remove an agent pod with a departure animation.
    func removeAgent(name: String) {
        guard let pod = pods[name] else { return }
        pods.removeValue(forKey: name)
        let depart = SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: -40, duration: 0.35),
                SKAction.fadeOut(withDuration: 0.35)
            ]),
            SKAction.removeFromParent()
        ])
        pod.run(depart)
    }

    /// Update a single agent's visual state.
    func setAgentState(_ name: String, state: OfficeAgentState) {
        pods[name]?.setState(state)
    }

    // MARK: - Debate Mode ──────────────────────────────────────────────

    func startDebate(participants: [String]) {
        guard !isDebateActive else { return }
        isDebateActive = true
        currentDebateParticipants = participants

        // Materialise the table
        let table = buildDebateTable()
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        table.position = center
        table.alpha = 0
        table.zPosition = 0
        addChild(table)
        debateTable = table
        table.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.1),
            SKAction.fadeIn(withDuration: 0.7)
        ]))

        // Warp participants to table seats
        let radius: CGFloat = 185
        for (i, name) in participants.enumerated() {
            guard let pod = pods[name] else { continue }
            let angle = CGFloat(i) / CGFloat(max(participants.count, 1)) * 2 * .pi - .pi / 2
            let seat = CGPoint(x: center.x + cos(angle) * radius,
                               y: center.y + sin(angle) * (radius * 0.62))

            let warp = SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.12 + 0.4),
                SKAction.run { [weak self, weak pod] in
                    guard let self = self, let pod = pod else { return }
                    self.addWarpTrail(to: pod, destination: seat, duration: 0.18)
                },
                SKAction.scale(to: 0.25, duration: 0.18),
                SKAction.move(to: seat, duration: 0),
                SKAction.scale(to: 1, duration: 0.38)
            ])
            warp.timingMode = .easeOut
            pod.run(warp) { [weak pod] in pod?.setState(.debating) }
        }
    }

    func endDebate() {
        guard isDebateActive else { return }
        isDebateActive = false
        let participants = currentDebateParticipants
        currentDebateParticipants = []

        // Dismiss the table
        debateTable?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ]))
        debateTable = nil

        // Warp agents back to home
        for (i, name) in participants.enumerated() {
            guard let pod = pods[name] else { continue }
            let home = pod.homePosition
            let warpHome = SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.1 + 0.3),
                SKAction.run { [weak self, weak pod] in
                    guard let self = self, let pod = pod else { return }
                    self.addWarpTrail(to: pod, destination: home, duration: 0.18)
                },
                SKAction.scale(to: 0.25, duration: 0.18),
                SKAction.move(to: home, duration: 0),
                SKAction.scale(to: 1, duration: 0.4)
            ])
            warpHome.timingMode = .easeOut
            pod.run(warpHome) { [weak pod] in pod?.setState(.idle) }
        }
    }

    // MARK: - Visual Effects

    private func addWarpTrail(to node: SKNode, destination: CGPoint, duration: TimeInterval) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = nil // Use circles
        emitter.particleBirthRate = 2000
        emitter.particleLifetime = 0.4
        emitter.particlePositionRange = CGVector(dx: 10, dy: 10)
        emitter.particleSpeed = 50
        emitter.particleSpeedRange = 20
        emitter.emissionAngle = atan2(node.position.y - destination.y, node.position.x - destination.x)
        emitter.particleScale = 0.15
        emitter.particleScaleRange = 0.1
        emitter.particleAlpha = 0.8
        emitter.particleAlphaSpeed = -2.0
        emitter.particleColorSequence = nil
        emitter.particleColor = .cyan
        emitter.particleColorBlendFactor = 1.0
        
        emitter.position = node.position
        emitter.zPosition = -1 // Behind pods
        addChild(emitter)
        
        let move = SKAction.move(to: destination, duration: duration)
        let fadeOut = SKAction.fadeOut(withDuration: duration)
        let remove = SKAction.removeFromParent()
        
        emitter.run(SKAction.sequence([SKAction.group([move, fadeOut]), remove]))
    }

    // MARK: - Debate Table Builder ─────────────────────────────────────

    private func buildDebateTable() -> SKNode {
        let container = SKNode()

        // Outer ambient glow
        let outerRing = SKShapeNode(ellipseOf: CGSize(width: 400, height: 252))
        outerRing.fillColor = SKColor.cyan.withAlphaComponent(0.04)
        outerRing.strokeColor = SKColor.cyan.withAlphaComponent(0.12)
        outerRing.lineWidth = 2
        container.addChild(outerRing)

        // Table surface
        let table = SKShapeNode(ellipseOf: CGSize(width: 320, height: 200))
        table.fillColor = SKColor.white.withAlphaComponent(0.035)
        table.strokeColor = SKColor.cyan.withAlphaComponent(0.55)
        table.lineWidth = 1.5
        container.addChild(table)

        // Center beacon
        let beacon = SKShapeNode(circleOfRadius: 14)
        beacon.fillColor = SKColor.cyan.withAlphaComponent(0.25)
        beacon.strokeColor = SKColor.cyan.withAlphaComponent(0.7)
        beacon.lineWidth = 1
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 1.1),
            SKAction.scale(to: 1.0, duration: 1.1)
        ]))
        beacon.run(pulse)
        container.addChild(beacon)

        // Dashed orbit ring
        let orbit = SKShapeNode(circleOfRadius: 38)
        orbit.fillColor = .clear
        orbit.strokeColor = SKColor.cyan.withAlphaComponent(0.2)
        orbit.lineWidth = 1
        orbit.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 8)))
        container.addChild(orbit)

        // Label
        let label = SKLabelNode(text: "⚔ WAR ROOM ⚔")
        label.fontName  = "SFMono-Regular"
        label.fontSize  = 10
        label.fontColor = SKColor.cyan.withAlphaComponent(0.35)
        label.position  = CGPoint(x: 0, y: -7)
        container.addChild(label)

        return container
    }
}

// MARK: - SKColor Hex extension ────────────────────────────────────────

extension SKColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        self.init(
            red:   CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >>  8) / 255,
            blue:  CGFloat( rgb & 0x0000FF       ) / 255,
            alpha: 1
        )
    }
}
