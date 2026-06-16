import SpriteKit

// MARK: - AgentSpriteNode

/// A glassmorphic "workstation pod" that represents one agent on the office floor.
final class AgentSpriteNode: SKNode {

    // MARK: Visuals
    private let podBG: SKShapeNode
    private let accentGlow: SKShapeNode
    private let cropNode: SKCropNode
    private let avatarSprite: SKSpriteNode
    private let nameLabel: SKLabelNode
    private let roleTagNode: SKShapeNode
    private let roleTagText: SKLabelNode
    private let statusCapsule: SKShapeNode
    private let statusDot: SKShapeNode
    private let statusLabel: SKLabelNode
    private let terminalNode: SKShapeNode
    private let terminalText: SKLabelNode
    private let deskNode: SKShapeNode
    private let chairNode: SKShapeNode
    private let torsoNode: SKShapeNode
    private let keyboardNode: SKShapeNode

    // MARK: Data
    let agentName: String
    let accentColor: SKColor
    var homePosition: CGPoint = .zero
    private(set) var state: OfficeAgentState = .idle
    
    // Physical state
    var isBeingDragged = false
    var returnTask: Task<Void, Never>? = nil
    var lastPositionForFootprints: CGPoint = .zero

    // MARK: Init
    init(name: String, role: String, accentHex: String) {
        self.agentName = name
        self.accentColor = SKColor(hex: accentHex) ?? .cyan

        // ── Worker anchor: a person at a small workstation, not a profile card ──
        let podW: CGFloat = 78
        podBG = SKShapeNode(ellipseOf: CGSize(width: podW, height: 30))
        podBG.fillColor = SKColor.black.withAlphaComponent(0.16)
        podBG.strokeColor = .clear
        podBG.lineWidth = 1
        podBG.zPosition = 0

        // Accent glow ring
        accentGlow = SKShapeNode(ellipseOf: CGSize(width: podW + 10, height: 36))
        accentGlow.fillColor = .clear
        accentGlow.strokeColor = .clear
        accentGlow.lineWidth = 2
        accentGlow.alpha = 0
        accentGlow.zPosition = -1

        deskNode = SKShapeNode(rectOf: CGSize(width: 78, height: 28), cornerRadius: 4)
        deskNode.fillColor = SKColor(red: 0.50, green: 0.34, blue: 0.20, alpha: 1.0)
        deskNode.strokeColor = SKColor(red: 0.20, green: 0.14, blue: 0.09, alpha: 0.9)
        deskNode.lineWidth = 1
        deskNode.zPosition = 1

        chairNode = SKShapeNode(rectOf: CGSize(width: 34, height: 28), cornerRadius: 6)
        chairNode.fillColor = SKColor(red: 0.20, green: 0.23, blue: 0.34, alpha: 1.0)
        chairNode.strokeColor = SKColor.black.withAlphaComponent(0.25)
        chairNode.lineWidth = 1
        chairNode.zPosition = 2

        torsoNode = SKShapeNode(rectOf: CGSize(width: 28, height: 34), cornerRadius: 6)
        torsoNode.fillColor = (SKColor(hex: accentHex) ?? .cyan).withAlphaComponent(0.92)
        torsoNode.strokeColor = SKColor.black.withAlphaComponent(0.35)
        torsoNode.lineWidth = 1
        torsoNode.zPosition = 4

        keyboardNode = SKShapeNode(rectOf: CGSize(width: 36, height: 6), cornerRadius: 2)
        keyboardNode.fillColor = SKColor(white: 0.04, alpha: 0.85)
        keyboardNode.strokeColor = SKColor.cyan.withAlphaComponent(0.22)
        keyboardNode.lineWidth = 0.7
        keyboardNode.zPosition = 3

        // ── Avatar (circular crop) ──────────────────────────────────────
        let avatarD: CGFloat = 28
        let avatarName = "avatar_\(name.lowercased())"
        var texture: SKTexture
        if let url = Bundle.main.url(forResource: avatarName, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            texture = SKTexture(image: img)
        } else {
            let fallback = NSImage(size: NSSize(width: 128, height: 128))
            fallback.lockFocus()
            NSColor(hex: accentHex)?.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 128, height: 128)).fill()
            fallback.unlockFocus()
            texture = SKTexture(image: fallback)
        }

        avatarSprite = SKSpriteNode(texture: texture, size: CGSize(width: avatarD, height: avatarD))
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

        // Role tag capsule above worker.
        let tagW: CGFloat = 86, tagH: CGFloat = 16
        roleTagNode = SKShapeNode(rectOf: CGSize(width: tagW, height: tagH), cornerRadius: 4)
        roleTagNode.fillColor = SKColor.black.withAlphaComponent(0.7)
        roleTagNode.strokeColor = accentColor.withAlphaComponent(0.8)
        roleTagNode.lineWidth = 1.0
        roleTagNode.alpha = 0
        roleTagNode.zPosition = 3

        roleTagText = SKLabelNode(text: role.lowercased())
        roleTagText.fontName = "SFMono-Bold"
        roleTagText.fontSize = 7
        roleTagText.fontColor = .white
        roleTagText.verticalAlignmentMode = .center
        roleTagText.horizontalAlignmentMode = .center
        roleTagText.position = CGPoint(x: 0, y: 0)
        roleTagNode.addChild(roleTagText)

        // ── Status Capsule ──────────────────────────────────────────────
        let capW: CGFloat = 78, capH: CGFloat = 17
        statusCapsule = SKShapeNode(rectOf: CGSize(width: capW, height: capH), cornerRadius: 9)
        statusCapsule.fillColor = SKColor.black.withAlphaComponent(0.4)
        statusCapsule.strokeColor = SKColor(white: 1, alpha: 0.15)
        statusCapsule.lineWidth = 1.0
        statusCapsule.alpha = 0
        statusCapsule.zPosition = 3

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

        statusCapsule.addChild(statusDot)
        statusCapsule.addChild(statusLabel)

        // ── Terminal window ─────────────────────────────────────────────
        terminalNode = SKShapeNode(rectOf: CGSize(width: 100, height: 22), cornerRadius: 4)
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

        addChild(podBG)
        addChild(accentGlow)
        addChild(deskNode)
        addChild(chairNode)
        addChild(torsoNode)
        addChild(keyboardNode)
        addChild(cropNode)
        addChild(nameLabel)
        addChild(roleTagNode)
        addChild(statusCapsule)
        addChild(terminalNode)
        terminalNode.addChild(terminalText)

        let monitor = SKShapeNode(rectOf: CGSize(width: 24, height: 16), cornerRadius: 2)
        monitor.fillColor = SKColor(red: 0.03, green: 0.07, blue: 0.09, alpha: 1.0)
        monitor.strokeColor = accentColor.withAlphaComponent(0.55)
        monitor.lineWidth = 1
        monitor.position = CGPoint(x: -19, y: 6)
        monitor.zPosition = 4
        deskNode.addChild(monitor)

        let secondMonitor = SKShapeNode(rectOf: CGSize(width: 20, height: 13), cornerRadius: 2)
        secondMonitor.fillColor = SKColor(red: 0.03, green: 0.07, blue: 0.09, alpha: 1.0)
        secondMonitor.strokeColor = accentColor.withAlphaComponent(0.36)
        secondMonitor.lineWidth = 1
        secondMonitor.position = CGPoint(x: 13, y: 7)
        secondMonitor.zPosition = 4
        deskNode.addChild(secondMonitor)

        let armPath = CGMutablePath()
        armPath.move(to: CGPoint(x: -12, y: -3))
        armPath.addLine(to: CGPoint(x: -24, y: -20))
        armPath.move(to: CGPoint(x: 12, y: -3))
        armPath.addLine(to: CGPoint(x: 24, y: -20))
        let arms = SKShapeNode(path: armPath)
        arms.strokeColor = SKColor(red: 0.95, green: 0.74, blue: 0.55, alpha: 0.9)
        arms.lineWidth = 4
        arms.lineCap = .round
        arms.zPosition = 5
        torsoNode.addChild(arms)

        let body = SKPhysicsBody(circleOfRadius: 36)
        body.isDynamic = false
        body.affectedByGravity = false
        body.allowsRotation = false
        body.restitution = 0.8
        body.friction = 0.1
        body.linearDamping = 0.6
        self.physicsBody = body

        layout()
        startIdleBreathe()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func layout() {
        podBG.position         = CGPoint(x: 0, y: -20)
        accentGlow.position    = CGPoint(x: 0, y: -20)
        deskNode.position      = CGPoint(x: 0, y: -32)
        chairNode.position     = CGPoint(x: 0, y: -4)
        torsoNode.position     = CGPoint(x: 0, y: 8)
        keyboardNode.position  = CGPoint(x: 0, y: -24)
        cropNode.position      = CGPoint(x: 0, y: 31)
        nameLabel.position     = CGPoint(x: 0, y: 52)
        statusCapsule.position = CGPoint(x: 0, y: 69)
        roleTagNode.position   = CGPoint(x: 0, y: 74)
        terminalNode.position  = CGPoint(x: 0, y: -61)
        terminalText.position  = CGPoint(x: -47, y: -3)
    }

    func updateTheme(isDark: Bool) {
        if isDark {
            podBG.fillColor = SKColor(white: 1, alpha: 0.04)
            podBG.strokeColor = SKColor(white: 1, alpha: 0.12)
            statusCapsule.fillColor = SKColor.black.withAlphaComponent(0.4)
            statusCapsule.strokeColor = SKColor(white: 1, alpha: 0.15)
            nameLabel.fontColor = .white
            roleTagNode.fillColor = SKColor.black.withAlphaComponent(0.7)
            roleTagText.fontColor = .white
            deskNode.fillColor = SKColor(red: 0.50, green: 0.34, blue: 0.20, alpha: 1.0)
            chairNode.fillColor = SKColor(red: 0.20, green: 0.23, blue: 0.34, alpha: 1.0)
            if state == .idle {
                statusLabel.fontColor = SKColor(white: 1, alpha: 0.3)
                statusDot.fillColor = SKColor(white: 1, alpha: 0.25)
            }
        } else {
            podBG.fillColor = SKColor(white: 0, alpha: 0.04)
            podBG.strokeColor = SKColor(white: 0, alpha: 0.15)
            statusCapsule.fillColor = SKColor(white: 1, alpha: 0.6)
            statusCapsule.strokeColor = SKColor(white: 0, alpha: 0.15)
            nameLabel.fontColor = .black
            roleTagNode.fillColor = SKColor(white: 1, alpha: 0.8)
            roleTagText.fontColor = .black
            deskNode.fillColor = SKColor(red: 0.64, green: 0.48, blue: 0.31, alpha: 1.0)
            chairNode.fillColor = SKColor(red: 0.35, green: 0.39, blue: 0.52, alpha: 1.0)
            if state == .idle {
                statusLabel.fontColor = SKColor(white: 0, alpha: 0.4)
                statusDot.fillColor = SKColor(white: 0, alpha: 0.3)
    }
}

    }

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

    func startGrabAnimation() {
        cropNode.removeAction(forKey: "breathe")
        cropNode.removeAction(forKey: "bounce")
        cropNode.run(SKAction.scale(to: 1.12, duration: 0.15))
    }

    func endGrabAnimation() {
        cropNode.run(SKAction.scale(to: 1.0, duration: 0.15))
    }

    func setState(_ newState: OfficeAgentState, animated: Bool = true) {
        state = newState

        cropNode.removeAction(forKey: "breathe")
        cropNode.removeAction(forKey: "bounce")
        cropNode.removeAction(forKey: "typing_animation")
        cropNode.zRotation = 0
        removeAction(forKey: "glow_pulse")
        childNode(withName: "waiting_balloon")?.removeFromParent()
        childNode(withName: "coding_particles")?.removeFromParent()

        switch newState {
        case .idle:
            setStatusAppearance(text: "Idle", dotColor: SKColor(white: 1, alpha: 0.25))
            accentGlow.run(SKAction.fadeOut(withDuration: 0.4))
            hideTerminal()
            
            podBG.run(SKAction.fadeAlpha(to: 0.3, duration: 0.25))
            roleTagNode.run(SKAction.fadeAlpha(to: 0.0, duration: 0.25))
            statusCapsule.run(SKAction.fadeAlpha(to: 0.0, duration: 0.25))
            
            nameLabel.run(SKAction.move(to: CGPoint(x: 0, y: 52), duration: 0.25))
            nameLabel.run(SKAction.fadeAlpha(to: 0.65, duration: 0.25))
            
            cropNode.run(SKAction.scale(to: 0.9, duration: 0.3)) { [weak self] in
                self?.startIdleBreathe()
            }

        case .working, .speaking, .debating, .waiting:
            setStatusAppearance(text: newState == .working ? "Working" : newState == .speaking ? "Speaking…" : newState == .debating ? "Debating" : "⏳ Waiting", 
                                dotColor: newState == .working ? .green : newState == .speaking ? .cyan : newState == .debating ? .orange : .yellow)
            
            podBG.run(SKAction.fadeAlpha(to: 1.0, duration: 0.25))
            roleTagNode.run(SKAction.fadeAlpha(to: 0.78, duration: 0.25))
            statusCapsule.run(SKAction.fadeAlpha(to: 0.86, duration: 0.25))
            
            nameLabel.run(SKAction.move(to: CGPoint(x: 0, y: 52), duration: 0.25))
            nameLabel.run(SKAction.fadeAlpha(to: 1.0, duration: 0.25))
            
            if newState == .working {
                showGlowPulse()
                showTerminal()
                cropNode.run(SKAction.scale(to: 1.08, duration: 0.3))
                
                // Typing micro-wobble animation
                let typeAction = SKAction.repeatForever(SKAction.sequence([
                    SKAction.rotate(toAngle: 0.04, duration: 0.08),
                    SKAction.rotate(toAngle: -0.04, duration: 0.08)
                ]))
                cropNode.run(typeAction, withKey: "typing_animation")
                
                showCodingParticles()
            } else if newState == .speaking {
                showGlowPulse()
                let bounce = SKAction.repeatForever(SKAction.sequence([
                    SKAction.moveBy(x: 0, y: 7, duration: 0.22),
                    SKAction.moveBy(x: 0, y: -7, duration: 0.22)
                ]))
                cropNode.run(bounce, withKey: "bounce")
            } else if newState == .debating {
                showGlowPulse()
                cropNode.run(SKAction.scale(to: 1.05, duration: 0.3))
            } else if case .waiting(let blockedOn) = newState {
                showGlowPulse()
                showWaitingBalloon(text: "Wait: \(blockedOn)")
            }
        }
    }

    private func showCodingParticles() {
        childNode(withName: "coding_particles")?.removeFromParent()
        
        let emitter = SKEmitterNode()
        emitter.name = "coding_particles"
        
        emitter.particleColorSequence = nil
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColor = accentColor
        emitter.particleBirthRate = 12
        emitter.particleLifetime = 0.7
        emitter.particleSpeed = 22
        emitter.particleSpeedRange = 8
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = 0.4
        emitter.particleAlpha = 0.8
        emitter.particleAlphaSpeed = -1.1
        emitter.particleScale = 0.12
        emitter.particleScaleRange = 0.05
        emitter.position = CGPoint(x: 0, y: -46)
        emitter.zPosition = 3
        
        addChild(emitter)
    }

    private func showWaitingBalloon(text: String) {
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
        
        // Spawn floaty speech bubble in the parent scene
        if let scene = self.scene as? WarRoomScene {
            scene.spawnSpeechBubble(above: self, text: text)
        }
    }
}
