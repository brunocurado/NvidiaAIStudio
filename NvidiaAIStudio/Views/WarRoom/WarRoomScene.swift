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
    
    // Physical state
    var isBeingDragged = false
    var returnTask: Task<Void, Never>? = nil

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

        // Physics Body for satisfying drag-and-throw collisions
        let body = SKPhysicsBody(circleOfRadius: 46)
        body.isDynamic = false // Static by default, turned active on drag/throw
        body.affectedByGravity = false
        body.allowsRotation = false
        body.restitution = 0.8 // Satisfying bouncy glass pods
        body.friction = 0.1
        body.linearDamping = 0.6
        self.physicsBody = body

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

    // MARK: - Drag Animation Encapsulation

    func startGrabAnimation() {
        cropNode.removeAction(forKey: "breathe")
        cropNode.removeAction(forKey: "bounce")
        cropNode.run(SKAction.scale(to: 1.12, duration: 0.15))
    }

    func endGrabAnimation() {
        cropNode.run(SKAction.scale(to: 1.0, duration: 0.15))
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
    }

    private func hideTerminal() {
        terminalNode.run(SKAction.fadeOut(withDuration: 0.3))
    }

    func updateLogText(_ text: String) {
        terminalText.text = "▶ \(text)"
        if terminalNode.alpha == 0 {
            terminalNode.run(SKAction.fadeIn(withDuration: 0.4))
        }
    }
}

// MARK: - War Room Scene

/// The main SpriteKit scene representing the glassmorphic virtual office.
final class WarRoomScene: SKScene {

    // MARK: Agent registry
    private(set) var pods: [String: AgentPodNode] = [:]
    private var layoutCounter: Int = 0

    // MARK: Debate table & Data streams
    private var debateTable: SKNode?
    private var isDebateActive = false
    private var currentDebateParticipants: [String] = []
    private var debateLaserContainer = SKNode()

    // MARK: Dragging support
    private var selectedPodForDrag: AgentPodNode? = nil
    private var dragStartVelocity: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var lastDragPos: CGPoint = .zero

    // MARK: Layout constants
    private let columns        = 4
    private let podSpacingX: CGFloat = 148
    private let podSpacingY: CGFloat = 155
    private let topPadding:  CGFloat = 110

    // MARK: - Setup ────────────────────────────────────────────────────

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        setupBackground()

        // Define screen borders for physics bounce
        self.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: self.size))
        self.physicsBody?.restitution = 0.8
        self.physicsBody?.friction = 0.1
        self.physicsBody?.categoryBitMask = 1

        // Add laser container
        debateLaserContainer.zPosition = -2
        addChild(debateLaserContainer)

        // Enable user interaction
        isUserInteractionEnabled = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        self.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: self.size))
        self.physicsBody?.restitution = 0.8
        self.physicsBody?.friction = 0.1
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

        // ── Rest Lounge Area Decoration ────────────────────────────────
        let loungeW: CGFloat = 220, loungeH: CGFloat = 165
        let loungeRect = SKShapeNode(rectOf: CGSize(width: loungeW, height: loungeH), cornerRadius: 16)
        loungeRect.fillColor = SKColor.magenta.withAlphaComponent(0.025)
        loungeRect.strokeColor = SKColor.magenta.withAlphaComponent(0.12)
        loungeRect.lineWidth = 1.5
        loungeRect.position = CGPoint(x: size.width - loungeW/2 - 20, y: size.height - loungeH/2 - 20)
        loungeRect.name = "lounge_bg"
        loungeRect.zPosition = -6
        addChild(loungeRect)

        let loungeLabel = SKLabelNode(text: "☕ REST LOUNGE")
        loungeLabel.fontName = "SFProDisplay-Bold"
        loungeLabel.fontSize = 9
        loungeLabel.fontColor = SKColor.magenta.withAlphaComponent(0.3)
        loungeLabel.position = CGPoint(x: 0, y: loungeH/2 - 22)
        loungeRect.addChild(loungeLabel)

        // Lounge bubble emitters (steam/coffee ambient effect)
        let steamEmitter = SKEmitterNode()
        steamEmitter.particleBirthRate = 3
        steamEmitter.particleLifetime = 4.0
        steamEmitter.particlePositionRange = CGVector(dx: loungeW - 40, dy: 10)
        steamEmitter.particleSpeed = 10
        steamEmitter.particleSpeedRange = 5
        steamEmitter.emissionAngle = .pi / 2
        steamEmitter.particleScale = 0.08
        steamEmitter.particleScaleRange = 0.05
        steamEmitter.particleAlpha = 0.15
        steamEmitter.particleAlphaSpeed = -0.05
        steamEmitter.particleColor = .magenta
        steamEmitter.position = CGPoint(x: 0, y: -loungeH/2 + 20)
        loungeRect.addChild(steamEmitter)

        // ── Desks (transparent shells under grid positions) ──────────
        for i in 0..<8 {
            let pos = gridPosition(for: i)
            let desk = SKShapeNode(rectOf: CGSize(width: 116, height: 60), cornerRadius: 8)
            desk.fillColor = SKColor.cyan.withAlphaComponent(0.012)
            desk.strokeColor = SKColor.cyan.withAlphaComponent(0.06)
            desk.lineWidth = 1
            desk.position = CGPoint(x: pos.x, y: pos.y - 20)
            desk.zPosition = -5
            addChild(desk)

            // Screen glow symbol
            let screen = SKShapeNode(rectOf: CGSize(width: 22, height: 14), cornerRadius: 2)
            screen.fillColor = SKColor.cyan.withAlphaComponent(0.08)
            screen.strokeColor = SKColor.cyan.withAlphaComponent(0.25)
            screen.lineWidth = 1
            screen.position = CGPoint(x: 0, y: 10)
            desk.addChild(screen)

            let stand = SKShapeNode(rectOf: CGSize(width: 8, height: 4))
            stand.fillColor = SKColor.cyan.withAlphaComponent(0.2)
            stand.strokeColor = .clear
            stand.position = CGPoint(x: 0, y: 0)
            desk.addChild(stand)

            let label = SKLabelNode(text: "DESK \(i+1)")
            label.fontName = "SFProText-Regular"
            label.fontSize = 6
            label.fontColor = SKColor.cyan.withAlphaComponent(0.22)
            label.position = CGPoint(x: 0, y: -20)
            desk.addChild(label)
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

    // MARK: - Location Calculators ─────────────────────────────────────

    private func gridPosition(for index: Int) -> CGPoint {
        let col = index % columns
        let row = index / columns
        let totalWidth = CGFloat(columns - 1) * podSpacingX
        let startX = (size.width - totalWidth) / 2
        let startY = size.height - topPadding
        return CGPoint(x: startX + CGFloat(col) * podSpacingX,
                       y: startY - CGFloat(row) * podSpacingY)
    }

    private func loungePosition(for name: String) -> CGPoint {
        let hash = abs(name.hashValue)
        let lx = size.width - 240 + 40 + CGFloat(hash % 140)
        let ly = size.height - 180 + 40 + CGFloat((hash / 10) % 100)
        return CGPoint(x: lx, y: ly)
    }

    // MARK: - Public API ───────────────────────────────────────────────

    func spawnAgent(name: String, role: String, accentHex: String, index: Int) {
        guard pods[name] == nil else { return }

        let pod = AgentPodNode(name: name, role: role, accentHex: accentHex)
        let target = loungePosition(for: name)
        pod.homePosition = target
        pod.zPosition = 1

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

    func setAgentState(_ name: String, state: OfficeAgentState) {
        guard let pod = pods[name] else { return }
        
        pod.setState(state)

        // 1. Assign proper homePosition coordinates based on State
        var newHome = pod.homePosition
        switch state {
        case .idle:
            newHome = loungePosition(for: name)
        case .working, .speaking, .waiting:
            // Regress to assigned developer desk
            if let idx = Array(pods.keys).sorted().firstIndex(of: name) {
                newHome = gridPosition(for: idx)
            }
        case .debating:
            // Assigned via circular seats in startDebate()
            return
        }

        pod.homePosition = newHome

        // 2. Perform smooth walking movement (wobble) to newHome
        if !pod.isBeingDragged && pod.position != newHome {
            pod.removeAction(forKey: "walk")
            pod.removeAction(forKey: "wobble")

            let dist = hypot(pod.position.x - newHome.x, pod.position.y - newHome.y)
            let dur = max(0.5, Double(dist) / 180.0) // 180 px/sec walking speed

            let walk = SKAction.move(to: newHome, duration: dur)
            walk.timingMode = .easeInEaseOut

            let wobble = SKAction.repeatForever(SKAction.sequence([
                SKAction.rotate(toAngle: 0.06, duration: 0.12),
                SKAction.rotate(toAngle: -0.06, duration: 0.12)
            ]))

            let completion = SKAction.run { [weak pod] in
                guard let pod = pod else { return }
                pod.removeAction(forKey: "wobble")
                pod.zRotation = 0
                pod.setState(pod.state)
            }

            pod.run(wobble, withKey: "wobble")
            pod.run(SKAction.sequence([walk, completion]), withKey: "walk")
        }
    }

    func updateTerminalLog(for agentName: String, text: String) {
        pods[agentName]?.updateLogText(text)
    }

    // MARK: - Drag & Toss Physics (macOS mouse handlers) ──────────────────

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let touchedNodes = nodes(at: location)

        for node in touchedNodes {
            var current: SKNode? = node
            while current != nil {
                if let pod = current as? AgentPodNode {
                    selectedPodForDrag = pod
                    pod.isBeingDragged = true
                    pod.returnTask?.cancel()

                    // Enable dynamic physics to crash into other pods
                    pod.physicsBody?.isDynamic = true
                    pod.physicsBody?.affectedByGravity = false
                    pod.physicsBody?.velocity = .zero
                    pod.physicsBody?.angularVelocity = 0

                    pod.startGrabAnimation()

                    lastDragPos = location
                    lastDragTime = event.timestamp
                    return
                }
                current = current?.parent
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pod = selectedPodForDrag else { return }
        let location = event.location(in: self)

        // Move to mouse position
        pod.position = location

        let dt = event.timestamp - lastDragTime
        if dt > 0 {
            dragStartVelocity = CGPoint(
                x: (location.x - lastDragPos.x) / CGFloat(dt),
                y: (location.y - lastDragPos.y) / CGFloat(dt)
            )
        }
        lastDragPos = location
        lastDragTime = event.timestamp
    }

    override func mouseUp(with event: NSEvent) {
        guard let pod = selectedPodForDrag else { return }
        pod.isBeingDragged = false
        selectedPodForDrag = nil
        pod.endGrabAnimation()

        // Toss with force physics impulse
        let velocityMultiplier: CGFloat = 0.05
        let impulse = CGVector(
            dx: dragStartVelocity.x * velocityMultiplier,
            dy: dragStartVelocity.y * velocityMultiplier
        )
        pod.physicsBody?.applyImpulse(impulse)

        // Return home walk after 2.5 seconds
        triggerReturnHome(for: pod)
    }

    private func triggerReturnHome(for pod: AgentPodNode) {
        pod.returnTask?.cancel()
        pod.returnTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self, weak pod] in
                guard let self = self, let pod = pod else { return }
                guard !pod.isBeingDragged else { return }

                pod.physicsBody?.isDynamic = false
                pod.physicsBody?.velocity = .zero
                pod.physicsBody?.angularVelocity = 0
                pod.zRotation = 0

                // Particle trace trail back home
                self.addWarpTrail(to: pod, destination: pod.homePosition, duration: 0.15)

                let walk = SKAction.move(to: pod.homePosition, duration: 1.0)
                walk.timingMode = .easeInEaseOut

                let wobble = SKAction.repeatForever(SKAction.sequence([
                    SKAction.rotate(toAngle: 0.06, duration: 0.12),
                    SKAction.rotate(toAngle: -0.06, duration: 0.12)
                ]))

                let completion = SKAction.run { [weak pod] in
                    guard let pod = pod else { return }
                    pod.removeAction(forKey: "wobble")
                    pod.zRotation = 0
                    pod.setState(pod.state)
                }

                pod.run(wobble, withKey: "wobble")
                pod.run(SKAction.sequence([walk, completion]))
            }
        }
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

        // Warp and slide participants to circular debate seats
        let radius: CGFloat = 185
        for (i, name) in participants.enumerated() {
            guard let pod = pods[name] else { continue }
            let angle = CGFloat(i) / CGFloat(max(participants.count, 1)) * 2 * .pi - .pi / 2
            let seat = CGPoint(x: center.x + cos(angle) * radius,
                               y: center.y + sin(angle) * (radius * 0.62))

            pod.homePosition = seat
            let warp = SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.12 + 0.4),
                SKAction.run { [weak self, weak pod] in
                    guard let self = self, let pod = pod else { return }
                    self.addWarpTrail(to: pod, destination: seat, duration: 0.5)
                },
                SKAction.group([
                    SKAction.move(to: seat, duration: 0.5),
                    SKAction.scale(to: 1.05, duration: 0.5)
                ])
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

        // Slide agents back to home positions
        for (i, name) in participants.enumerated() {
            guard let pod = pods[name] else { continue }
            let home = loungePosition(for: name) // Return to rest Lounge
            pod.homePosition = home
            let warpHome = SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.1 + 0.3),
                SKAction.run { [weak self, weak pod] in
                    guard let self = self, let pod = pod else { return }
                    self.addWarpTrail(to: pod, destination: home, duration: 0.5)
                },
                SKAction.group([
                    SKAction.move(to: home, duration: 0.5),
                    SKAction.scale(to: 1.0, duration: 0.5)
                ])
            ])
            warpHome.timingMode = .easeOut
            pod.run(warpHome) { [weak pod] in pod?.setState(.idle) }
        }
    }

    // MARK: - Visual Effects ───────────────────────────────────────────

    private func addWarpTrail(to node: SKNode, destination: CGPoint, duration: TimeInterval) {
        let emitter = SKEmitterNode()
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
        emitter.particleColor = .cyan
        emitter.particleColorBlendFactor = 1.0
        
        emitter.position = node.position
        emitter.zPosition = -1
        addChild(emitter)
        
        let move = SKAction.move(to: destination, duration: duration)
        let fadeOut = SKAction.fadeOut(withDuration: duration)
        let remove = SKAction.removeFromParent()
        
        emitter.run(SKAction.sequence([SKAction.group([move, fadeOut]), remove]))
    }

    private func emitSpark(from start: CGPoint, to end: CGPoint) {
        let spark = SKShapeNode(circleOfRadius: 2.0)
        spark.fillColor = .cyan
        spark.strokeColor = .clear
        spark.position = start
        spark.zPosition = -1
        addChild(spark)

        let move = SKAction.move(to: end, duration: 0.45)
        let fade = SKAction.fadeOut(withDuration: 0.45)
        let remove = SKAction.removeFromParent()

        spark.run(SKAction.sequence([
            SKAction.group([move, fade]),
            remove
        ]))
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)

        // Clear old debate lasers
        debateLaserContainer.removeAllChildren()

        guard isDebateActive else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        for name in currentDebateParticipants {
            guard let pod = pods[name] else { continue }

            let path = CGMutablePath()
            path.move(to: pod.position)
            path.addLine(to: center)

            let laser = SKShapeNode(path: path)
            let baseColor = pod.accentColor

            if pod.state == .speaking {
                laser.strokeColor = baseColor
                laser.lineWidth = 2.0
                
                let alpha = 0.6 + CGFloat(sin(currentTime * 12.0)) * 0.25
                laser.alpha = alpha

                if Double.random(in: 0...1) < 0.25 {
                    emitSpark(from: pod.position, to: center)
                }
            } else {
                laser.strokeColor = baseColor.withAlphaComponent(0.22)
                laser.lineWidth = 1.0
            }

            debateLaserContainer.addChild(laser)
        }
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
