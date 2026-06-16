import SpriteKit

// MARK: - War Room Scene

/// The main SpriteKit scene representing the glassmorphic virtual office.
final class WarRoomScene: SKScene {

    // MARK: Agent registry
    private(set) var pods: [String: AgentSpriteNode] = [:]

    // MARK: Debate table & Data streams
    private var debateTable: SKNode?
    private(set) var isDebateActive = false
    private var currentDebateParticipants: [String] = []
    private var debateLaserContainer = SKNode()
    private var lastPacketTime: TimeInterval = 0
    private var debateCenter: CGPoint = .zero

    // MARK: Dragging support
    private var selectedPodForDrag: AgentSpriteNode? = nil
    private var dragStartVelocity: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var lastDragPos: CGPoint = .zero

    // MARK: Theme state
    var isDarkTheme = true

    // MARK: Live details & drone
    private var droneNode: SKNode?
    private var lastAmbientPacketTime: TimeInterval = 0

    private var layout: WarRoomLayout {
        WarRoomLayout(size: size)
    }

    // MARK: - Setup ────────────────────────────────────────────────────

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        setupBackground()

        self.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: self.size))
        self.physicsBody?.restitution = 0.8
        self.physicsBody?.friction = 0.1
        self.physicsBody?.categoryBitMask = 1

        debateLaserContainer.zPosition = -2
        addChild(debateLaserContainer)

        isUserInteractionEnabled = true
        setupDrone()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        self.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: self.size))
        self.physicsBody?.restitution = 0.8
        self.physicsBody?.friction = 0.1

        updateFloorZones()

        // Align all idle/work pods to their fresh size/bounds
        for (name, pod) in pods {
            let targetPos: CGPoint
            if pod.state == .idle {
                targetPos = layout.deskPosition(index: getDeskIndex(for: name))
            } else if pod.state == .debating || (isDebateActive && currentDebateParticipants.contains(name)) {
                if let idx = currentDebateParticipants.firstIndex(of: name) {
                    targetPos = layout.debateSeat(index: idx, count: currentDebateParticipants.count)
                } else {
                    targetPos = pod.homePosition
                }
            } else if let idx = Array(pods.keys).sorted().firstIndex(of: name) {
                targetPos = layout.deskPosition(index: idx)
            } else {
                targetPos = pod.homePosition
            }
            pod.homePosition = targetPos
            if !pod.isBeingDragged {
                pod.position = targetPos
            }
        }

        if let table = debateTable {
            table.position = layout.meetingCenter
        }
    }

    private func setupBackground() {
        setupFloorTexture()
        let layout = self.layout

        let floorBG = SKShapeNode(rectOf: size)
        floorBG.name = "floor_background"
        floorBG.fillColor = isDarkTheme
            ? SKColor(red: 0.06, green: 0.04, blue: 0.025, alpha: 0.30)
            : SKColor(red: 0.96, green: 0.91, blue: 0.82, alpha: 0.18)
        floorBG.strokeColor = .clear
        floorBG.position = CGPoint(x: size.width / 2, y: size.height / 2)
        floorBG.zPosition = -9.5
        addChild(floorBG)

        recreateGridAndHatches()

        let wall = SKShapeNode(rectOf: CGSize(width: size.width - 210, height: 92), cornerRadius: 0)
        wall.name = "back_wall"
        wall.fillColor = isDarkTheme
            ? SKColor(red: 0.20, green: 0.13, blue: 0.09, alpha: 0.70)
            : SKColor(red: 0.76, green: 0.66, blue: 0.54, alpha: 0.55)
        wall.strokeColor = SKColor.black.withAlphaComponent(0.12)
        wall.position = layout.backWallPosition
        wall.zPosition = -8.6
        addChild(wall)

        let header = SKLabelNode(text: "NVIDIA AI STUDIO - WAR ROOM")
        header.name = "room_header"
        header.fontName = "SFMono-Bold"
        header.fontSize = 13
        header.fontColor = SKColor(red: 1.0, green: 0.79, blue: 0.36, alpha: 0.82)
        header.position = layout.headerPosition
        header.zPosition = -5
        addChild(header)

        for (i, x) in stride(from: 110, through: max(110, size.width - 110), by: 180).enumerated() {
            let lamp = SKNode()
            lamp.name = "ceiling_lamp_\(i)"
            lamp.zPosition = -5
            lamp.position = CGPoint(x: x, y: size.height - 84)

            let cable = SKShapeNode(rectOf: CGSize(width: 1, height: 34))
            cable.fillColor = SKColor.black.withAlphaComponent(0.35)
            cable.strokeColor = .clear
            cable.position = CGPoint(x: 0, y: 18)
            lamp.addChild(cable)

            let bulb = SKShapeNode(circleOfRadius: 7)
            bulb.fillColor = SKColor(red: 1.0, green: 0.78, blue: 0.32, alpha: 0.85)
            bulb.strokeColor = SKColor(red: 1.0, green: 0.90, blue: 0.55, alpha: 0.45)
            bulb.lineWidth = 1
            lamp.addChild(bulb)

            let glow = SKShapeNode(ellipseOf: CGSize(width: 110, height: 55))
            glow.fillColor = SKColor(red: 1.0, green: 0.62, blue: 0.18, alpha: 0.045)
            glow.strokeColor = .clear
            glow.position = CGPoint(x: 0, y: -28)
            glow.zPosition = -1
            lamp.addChild(glow)

            addChild(lamp)
        }

        let workZoneBorder = SKShapeNode()
        workZoneBorder.name = "work_zone_border"
        workZoneBorder.fillColor = isDarkTheme
            ? SKColor(red: 0.08, green: 0.11, blue: 0.12, alpha: 0.22)
            : SKColor(red: 0.74, green: 0.87, blue: 0.86, alpha: 0.26)
        workZoneBorder.strokeColor = SKColor.cyan.withAlphaComponent(0.18)
        workZoneBorder.lineWidth = 1.0
        workZoneBorder.zPosition = -7
        addChild(workZoneBorder)

        let zoneLabel = SKLabelNode(text: "WORK FLOOR")
        zoneLabel.name = "zone_label"
        zoneLabel.fontName = "SFMono-Bold"
        zoneLabel.fontSize = 9
        zoneLabel.fontColor = SKColor.cyan.withAlphaComponent(0.45)
        zoneLabel.zPosition = -6
        addChild(zoneLabel)

        for i in 0..<20 {
            let deskSet = OfficePropFactory.makeDeskSet(index: i)
            addChild(deskSet.shadow)
            addChild(deskSet.desk)
            addChild(deskSet.chair)
        }

        let lounge = OfficePropFactory.makeLoungeShell(isDarkTheme: isDarkTheme)
        addChild(lounge.floor)
        addChild(lounge.panel)

        let meetingPlate = SKShapeNode(ellipseOf: CGSize(width: 286, height: 166))
        meetingPlate.name = "meeting_plate"
        meetingPlate.fillColor = isDarkTheme
            ? SKColor(red: 0.08, green: 0.12, blue: 0.13, alpha: 0.20)
            : SKColor(red: 0.80, green: 0.88, blue: 0.86, alpha: 0.28)
        meetingPlate.strokeColor = SKColor.cyan.withAlphaComponent(0.18)
        meetingPlate.lineWidth = 1.0
        meetingPlate.zPosition = -7
        
        let meetingInner = SKShapeNode(ellipseOf: CGSize(width: 260, height: 148))
        meetingInner.fillColor = .clear
        meetingInner.strokeColor = SKColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 0.08)
        meetingInner.lineWidth = 0.5
        meetingPlate.addChild(meetingInner)
        
        let centerCross = SKShapeNode()
        let crossPath = CGMutablePath()
        crossPath.move(to: CGPoint(x: -8, y: 0))
        crossPath.addLine(to: CGPoint(x: 8, y: 0))
        crossPath.move(to: CGPoint(x: 0, y: -8))
        crossPath.addLine(to: CGPoint(x: 0, y: 8))
        centerCross.path = crossPath
        centerCross.strokeColor = SKColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 0.25)
        centerCross.lineWidth = 0.5
        meetingPlate.addChild(centerCross)

        addChild(meetingPlate)

        let meetingLabel = SKLabelNode(text: "STANDUP")
        meetingLabel.name = "meeting_label"
        meetingLabel.fontName = "SFMono-Bold"
        meetingLabel.fontSize = 9
        meetingLabel.fontColor = SKColor.cyan.withAlphaComponent(0.42)
        meetingLabel.zPosition = -6
        addChild(meetingLabel)

        // ── Server Rack ───────────────────────────────────────────────
        setupMainframe()
        setupWhiteboard()
        setupEnvironmentalProps()

        let watermark = SKLabelNode(text: "NVIDIA AI STUDIO - COMMAND CENTER")
        watermark.name = "watermark_label"
        watermark.fontName = "SFMono-Regular"
        watermark.fontSize = 9
        watermark.fontColor = SKColor.white.withAlphaComponent(0.06)
        watermark.position = CGPoint(x: size.width / 2, y: 14)
        watermark.zPosition = -7
        addChild(watermark)

        updateFloorZones()
    }

    private func updateFloorZones() {
        let layout = self.layout
        let loungeW = layout.loungeSize.width
        let loungeH = layout.loungeSize.height
        let loungeCenter = layout.loungeCenter
        let meetingCenter = layout.meetingCenter
        let workRect = layout.workRect
        
        setupFloorTexture()
        setupEnvironmentalProps()

        if let wall = childNode(withName: "back_wall") as? SKShapeNode {
            wall.path = CGPath(rect: layout.backWallFrame, transform: nil)
            wall.position = layout.backWallPosition
        }
        if let header = childNode(withName: "room_header") as? SKLabelNode {
            header.position = layout.headerPosition
        }
        
        if let loungeFloor = childNode(withName: "lounge_floor") as? SKShapeNode {
            loungeFloor.path = CGPath(roundedRect: CGRect(x: -loungeW/2 - 5, y: -loungeH/2 - 5, width: loungeW + 10, height: loungeH + 10), cornerWidth: 20, cornerHeight: 20, transform: nil)
            loungeFloor.position = loungeCenter
        }
        if let lounge = childNode(withName: "lounge_bg") as? SKShapeNode {
            let rect = CGRect(x: -loungeW/2, y: -loungeH/2, width: loungeW, height: loungeH)
            lounge.path = createCornerBracketsPath(rect: rect, cornerRadius: 16, bracketLength: 26)
            lounge.position = loungeCenter
            
            if let lbl = lounge.childNode(withName: "lounge_lbl") {
                lbl.position = CGPoint(x: 0, y: loungeH/2 - 22)
            }
            if let emitter = lounge.childNode(withName: "lounge_steam") as? SKEmitterNode {
                emitter.position = CGPoint(x: 0, y: -loungeH/2 + 24)
                emitter.particlePositionRange = CGVector(dx: loungeW - 40, dy: 10)
            }
            for i in 0..<3 {
                if let seat = lounge.childNode(withName: "lounge_seat_\(i)") {
                    seat.position = CGPoint(x: -62 + CGFloat(i) * 62, y: -18)
                }
            }
        }
        
        if let workZone = childNode(withName: "work_zone_border") as? SKShapeNode {
            workZone.path = createCornerBracketsPath(rect: workRect, cornerRadius: 16, bracketLength: 32)
        }
        if let zoneLabel = childNode(withName: "zone_label") {
            zoneLabel.position = CGPoint(x: workRect.minX + 56, y: workRect.maxY - 28)
        }
        
        if let meetingPlate = childNode(withName: "meeting_plate") as? SKShapeNode {
            meetingPlate.position = meetingCenter
        }
        if let meetingLabel = childNode(withName: "meeting_label") {
            meetingLabel.position = CGPoint(x: meetingCenter.x, y: meetingCenter.y - 68)
        }
        
        if let board = childNode(withName: "scrum_board") {
            board.position = layout.boardPosition
        }
        if let mainframe = childNode(withName: "mainframe_crop") {
            mainframe.position = layout.mainframePosition
        }
        
        for i in 0..<20 {
            let pos = layout.deskPosition(index: i)
            if let shadow = childNode(withName: "desk_shadow_\(i)") {
                shadow.position = CGPoint(x: pos.x, y: pos.y - 30)
            }
            if let desk = childNode(withName: "desk_\(i)") {
                desk.position = CGPoint(x: pos.x, y: pos.y - 28)
            }
            if let chair = childNode(withName: "chair_\(i)") {
                chair.position = CGPoint(x: pos.x, y: pos.y + 6)
            }
        }
        
        setupOfficePathways()
        recreateGridAndHatches()
    }

    private func setupOfficePathways() {
        childNode(withName: "pathways_layer")?.removeFromParent()
        let layout = self.layout
        
        let pathwaysLayer = SKNode()
        pathwaysLayer.name = "pathways_layer"
        pathwaysLayer.zPosition = -8
        
        let workCenter = layout.workCenter
        let loungeCenter = layout.loungeCenter
        let meetingCenter = layout.meetingCenter
        let serverCenter = layout.mainframePosition
        
        // 1. Work Area to Standby Lounge (Purple)
        let pathWL = CGMutablePath()
        pathWL.move(to: workCenter)
        pathWL.addQuadCurve(to: loungeCenter, control: CGPoint(x: size.width / 2, y: size.height - 150))
        let shapeWL = SKShapeNode(path: pathWL)
        shapeWL.strokeColor = isDarkTheme
            ? SKColor(red: 0.7, green: 0.3, blue: 0.8, alpha: 0.15)
            : SKColor(red: 0.7, green: 0.3, blue: 0.8, alpha: 0.22)
        shapeWL.lineWidth = 1.5
        pathwaysLayer.addChild(shapeWL)
        
        // 2. Work Area to Meeting Area (Cyan)
        let pathWM = CGMutablePath()
        pathWM.move(to: workCenter)
        pathWM.addQuadCurve(to: meetingCenter, control: CGPoint(x: 260, y: 220))
        let shapeWM = SKShapeNode(path: pathWM)
        shapeWM.strokeColor = isDarkTheme
            ? SKColor(red: 0.0, green: 0.6, blue: 0.8, alpha: 0.15)
            : SKColor(red: 0.0, green: 0.6, blue: 0.8, alpha: 0.22)
        shapeWM.lineWidth = 1.5
        pathwaysLayer.addChild(shapeWM)
        
        // 3. Work Area to Mainframe Server (Green)
        let pathWS = CGMutablePath()
        pathWS.move(to: workCenter)
        pathWS.addQuadCurve(to: serverCenter, control: CGPoint(x: 100, y: size.height - 350))
        let shapeWS = SKShapeNode(path: pathWS)
        shapeWS.strokeColor = isDarkTheme
            ? SKColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 0.15)
            : SKColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 0.22)
        shapeWS.lineWidth = 1.5
        pathwaysLayer.addChild(shapeWS)
        
        // 4. Meeting Area to Standby Lounge (Orange)
        let pathML = CGMutablePath()
        pathML.move(to: meetingCenter)
        pathML.addQuadCurve(to: loungeCenter, control: CGPoint(x: size.width - 150, y: 190))
        let shapeML = SKShapeNode(path: pathML)
        shapeML.strokeColor = isDarkTheme
            ? SKColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 0.15)
            : SKColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 0.22)
        shapeML.lineWidth = 1.5
        pathwaysLayer.addChild(shapeML)
        
        addChild(pathwaysLayer)
    }

    // MARK: - Sci-Fi Visual Helpers ─────────────────────────────────────

    private func createCornerBracketsPath(rect: CGRect, cornerRadius: CGFloat, bracketLength: CGFloat) -> CGPath {
        OfficePropFactory.cornerBracketsPath(rect: rect, cornerRadius: cornerRadius, bracketLength: bracketLength)
    }

    private func setupFloorTexture() {
        childNode(withName: "floor_texture_container")?.removeFromParent()
        addChild(OfficePropFactory.makeFloorTexture(size: size, isDarkTheme: isDarkTheme))
    }

    private func setupEnvironmentalProps() {
        childNode(withName: "environmental_props")?.removeFromParent()
        
        let container = SKNode()
        container.name = "environmental_props"
        container.zPosition = -6

        let layout = self.layout
        let meetingCenter = layout.meetingCenter
        let tableShadow = SKShapeNode(ellipseOf: CGSize(width: 210, height: 88))
        tableShadow.fillColor = SKColor.black.withAlphaComponent(0.18)
        tableShadow.strokeColor = .clear
        tableShadow.position = CGPoint(x: meetingCenter.x, y: meetingCenter.y - 10)
        container.addChild(tableShadow)

        let table = SKShapeNode(ellipseOf: CGSize(width: 190, height: 74))
        table.name = "physical_conference_table"
        table.fillColor = SKColor(red: 0.38, green: 0.31, blue: 0.25, alpha: 0.95)
        table.strokeColor = SKColor.cyan.withAlphaComponent(0.28)
        table.lineWidth = 1.4
        table.position = meetingCenter
        table.zPosition = 1
        container.addChild(table)

        for i in 0..<8 {
            let angle = CGFloat(i) / 8.0 * 2 * .pi
            let chair = SKShapeNode(rectOf: CGSize(width: 28, height: 24), cornerRadius: 5)
            chair.fillColor = SKColor(red: 0.19, green: 0.21, blue: 0.30, alpha: 0.95)
            chair.strokeColor = SKColor.black.withAlphaComponent(0.22)
            chair.lineWidth = 0.8
            chair.position = CGPoint(
                x: meetingCenter.x + cos(angle) * 116,
                y: meetingCenter.y + sin(angle) * 48
            )
            chair.zRotation = angle
            container.addChild(chair)
        }

        let cooler = SKNode()
        cooler.name = "water_cooler"
        cooler.position = CGPoint(x: 94, y: size.height - 132)
        cooler.zPosition = 2
        let bottle = SKShapeNode(ellipseOf: CGSize(width: 24, height: 28))
        bottle.fillColor = SKColor.cyan.withAlphaComponent(0.18)
        bottle.strokeColor = SKColor.cyan.withAlphaComponent(0.45)
        bottle.lineWidth = 1
        bottle.position = CGPoint(x: 0, y: 14)
        cooler.addChild(bottle)
        let base = SKShapeNode(rectOf: CGSize(width: 26, height: 32), cornerRadius: 5)
        base.fillColor = SKColor(white: 0.82, alpha: 0.86)
        base.strokeColor = SKColor.black.withAlphaComponent(0.16)
        base.position = CGPoint(x: 0, y: -10)
        cooler.addChild(base)
        container.addChild(cooler)

        for (i, point) in [
            CGPoint(x: size.width - 78, y: 82),
            CGPoint(x: 150, y: 92),
            CGPoint(x: min(size.width - 150, size.width * 0.78), y: size.height - 142)
        ].enumerated() {
            let plant = SKNode()
            plant.name = "office_plant_\(i)"
            plant.position = point
            let pot = SKShapeNode(rectOf: CGSize(width: 28, height: 22), cornerRadius: 6)
            pot.fillColor = SKColor(red: 0.45, green: 0.23, blue: 0.15, alpha: 0.96)
            pot.strokeColor = SKColor.black.withAlphaComponent(0.18)
            pot.position = CGPoint(x: 0, y: -12)
            plant.addChild(pot)

            for leaf in 0..<6 {
                let angle = CGFloat(leaf) / 6.0 * 2 * .pi
                let blade = SKShapeNode(ellipseOf: CGSize(width: 12, height: 30))
                blade.fillColor = SKColor(red: 0.18, green: 0.52, blue: 0.25, alpha: 0.85)
                blade.strokeColor = SKColor(red: 0.07, green: 0.26, blue: 0.11, alpha: 0.45)
                blade.lineWidth = 0.5
                blade.position = CGPoint(x: cos(angle) * 8, y: sin(angle) * 5 + 6)
                blade.zRotation = angle
                plant.addChild(blade)
            }
            container.addChild(plant)
        }
        
        addChild(container)
    }

    private func recreateGridAndHatches() {
        childNode(withName: "grid_layer")?.removeFromParent()
        
        let gridLayer = SKNode()
        gridLayer.name = "grid_layer"
        gridLayer.zPosition = -9
        let step: CGFloat = 52
        let gc = isDarkTheme
            ? SKColor(white: 1.0, alpha: 0.02)
            : SKColor(white: 0.0, alpha: 0.03)

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

        let crosshairsPath = CGMutablePath()
        let crossSize: CGFloat = 3.0
        var gridY: CGFloat = 0
        while gridY <= size.height + step {
            var gridX: CGFloat = 0
            while gridX <= size.width + step {
                crosshairsPath.move(to: CGPoint(x: gridX - crossSize, y: gridY))
                crosshairsPath.addLine(to: CGPoint(x: gridX + crossSize, y: gridY))
                crosshairsPath.move(to: CGPoint(x: gridX, y: gridY - crossSize))
                crosshairsPath.addLine(to: CGPoint(x: gridX, y: gridY + crossSize))
                gridX += step
            }
            gridY += step
        }
        let crosshairsNode = SKShapeNode(path: crosshairsPath)
        crosshairsNode.strokeColor = isDarkTheme
            ? SKColor.cyan.withAlphaComponent(0.08)
            : SKColor.cyan.withAlphaComponent(0.12)
        crosshairsNode.lineWidth = 0.5
        gridLayer.addChild(crosshairsNode)

        let frameHatchPath = CGMutablePath()
        for i in 0..<4 {
            let offset = CGFloat(i) * 8
            frameHatchPath.move(to: CGPoint(x: 10 + offset, y: size.height - 10))
            frameHatchPath.addLine(to: CGPoint(x: 10, y: size.height - (10 + offset)))
            
            frameHatchPath.move(to: CGPoint(x: size.width - (10 + offset), y: size.height - 10))
            frameHatchPath.addLine(to: CGPoint(x: size.width - 10, y: size.height - (10 + offset)))
        }
        let frameHatchNode = SKShapeNode(path: frameHatchPath)
        frameHatchNode.strokeColor = isDarkTheme
            ? SKColor.cyan.withAlphaComponent(0.10)
            : SKColor.cyan.withAlphaComponent(0.15)
        frameHatchNode.lineWidth = 1.0
        gridLayer.addChild(frameHatchNode)
        
        addChild(gridLayer)
    }

    private func setupDrone() {
        childNode(withName: "office_drone")?.removeFromParent()
        
        let drone = SKNode()
        drone.name = "office_drone"
        drone.zPosition = 10
        
        let body = SKShapeNode(rectOf: CGSize(width: 16, height: 8), cornerRadius: 3)
        body.fillColor = SKColor(white: 0.15, alpha: 0.9)
        body.strokeColor = SKColor.cyan
        body.lineWidth = 1.0
        drone.addChild(body)
        
        let leftRotor = SKShapeNode(rectOf: CGSize(width: 4, height: 2), cornerRadius: 0.5)
        leftRotor.position = CGPoint(x: -10, y: 0)
        leftRotor.fillColor = .darkGray
        leftRotor.strokeColor = .cyan
        leftRotor.lineWidth = 0.5
        drone.addChild(leftRotor)
        
        let rightRotor = SKShapeNode(rectOf: CGSize(width: 4, height: 2), cornerRadius: 0.5)
        rightRotor.position = CGPoint(x: 10, y: 0)
        rightRotor.fillColor = .darkGray
        rightRotor.strokeColor = .cyan
        rightRotor.lineWidth = 0.5
        drone.addChild(rightRotor)
        
        let led = SKShapeNode(circleOfRadius: 1.2)
        led.fillColor = .red
        led.strokeColor = .clear
        led.position = CGPoint(x: 0, y: 2)
        drone.addChild(led)
        
        let blink = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 0.4),
            SKAction.run { led.fillColor = .green },
            SKAction.wait(forDuration: 0.4),
            SKAction.run { led.fillColor = .red }
        ]))
        led.run(blink)
        
        let scannerPath = CGMutablePath()
        scannerPath.move(to: .zero)
        scannerPath.addLine(to: CGPoint(x: -25, y: -90))
        scannerPath.addLine(to: CGPoint(x: 25, y: -90))
        scannerPath.closeSubpath()
        
        let scanner = SKShapeNode(path: scannerPath)
        scanner.fillColor = SKColor.cyan.withAlphaComponent(0.06)
        scanner.strokeColor = SKColor.cyan.withAlphaComponent(0.15)
        scanner.lineWidth = 0.5
        scanner.zPosition = -1
        drone.addChild(scanner)
        
        let pulseScanner = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.03, duration: 1.2),
            SKAction.fadeAlpha(to: 0.12, duration: 1.2)
        ]))
        scanner.run(pulseScanner)
        
        drone.position = CGPoint(x: size.width / 2, y: size.height / 2 + 100)
        addChild(drone)
        droneNode = drone
        
        let bob = SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 6, duration: 0.8),
            SKAction.moveBy(x: 0, y: -6, duration: 0.8)
        ]))
        bob.timingMode = .easeInEaseOut
        drone.run(bob)
        
        startDroneFlightLoop()
    }
    
    private func startDroneFlightLoop() {
        guard let drone = droneNode else { return }
        
        let chooseNextPath = SKAction.run { [weak self] in
            guard let self = self, let drone = self.droneNode else { return }
            
            let destX = CGFloat.random(in: 100...(self.size.width - 100))
            let destY = CGFloat.random(in: 100...(self.size.height - 100))
            let dest = CGPoint(x: destX, y: destY)
            
            let ctrlX = (drone.position.x + dest.x) / 2 + CGFloat.random(in: -100...100)
            let ctrlY = (drone.position.y + dest.y) / 2 + CGFloat.random(in: -100...100)
            
            let path = CGMutablePath()
            path.move(to: drone.position)
            path.addQuadCurve(to: dest, control: CGPoint(x: ctrlX, y: ctrlY))
            
            let duration = Double.random(in: 6.0...12.0)
            let fly = SKAction.follow(path, asOffset: false, orientToPath: false, duration: duration)
            fly.timingMode = .easeInEaseOut
            
            drone.run(fly, completion: { [weak self] in
                drone.run(SKAction.wait(forDuration: Double.random(in: 2.0...5.0)), completion: { [weak self] in
                    self?.startDroneFlightLoop()
                })
            })
        }
        
        drone.run(chooseNextPath)
    }

    private func spawnFootprint(at point: CGPoint, color: SKColor) {
        let printNode = SKShapeNode(circleOfRadius: 2.0)
        printNode.fillColor = color.withAlphaComponent(0.55)
        printNode.strokeColor = .clear
        printNode.zPosition = -2
        printNode.position = point
        addChild(printNode)
        
        let scale = SKAction.scale(to: 3.5, duration: 0.8)
        let fade = SKAction.fadeOut(withDuration: 0.8)
        let remove = SKAction.removeFromParent()
        
        printNode.run(SKAction.sequence([
            SKAction.group([scale, fade]),
            remove
        ]))
    }

    private func triggerFloorRipple(at point: CGPoint) {
        let ripple = SKShapeNode(circleOfRadius: 5)
        ripple.position = point
        ripple.strokeColor = SKColor.cyan.withAlphaComponent(0.8)
        ripple.lineWidth = 1.5
        ripple.fillColor = .clear
        ripple.zPosition = -1
        addChild(ripple)
        
        let scale = SKAction.scale(to: 15.0, duration: 0.6)
        scale.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: 0.6)
        let remove = SKAction.removeFromParent()
        
        ripple.run(SKAction.sequence([
            SKAction.group([scale, fade]),
            remove
        ]))
        
        for _ in 0..<8 {
            let spark = SKShapeNode(circleOfRadius: 1.5)
            spark.position = point
            spark.fillColor = SKColor(red: 0.0, green: 0.8, blue: 0.9, alpha: 0.9)
            spark.strokeColor = .clear
            spark.zPosition = -1
            addChild(spark)
            
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 15...45)
            let dest = CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance)
            
            let move = SKAction.move(to: dest, duration: Double.random(in: 0.3...0.6))
            move.timingMode = .easeOut
            let fadeSpark = SKAction.fadeOut(withDuration: Double.random(in: 0.3...0.6))
            
            spark.run(SKAction.sequence([
                SKAction.group([move, fadeSpark]),
                SKAction.removeFromParent()
            ]))
        }
    }

    func spawnDataPacket(onPath path: CGPath, color: SKColor) {
        let packet = SKShapeNode(circleOfRadius: 3.5)
        packet.fillColor = color
        packet.strokeColor = .clear
        packet.zPosition = -7
        
        let glow = SKShapeNode(circleOfRadius: 7)
        glow.fillColor = color.withAlphaComponent(0.35)
        glow.strokeColor = .clear
        glow.zPosition = -1
        packet.addChild(glow)
        
        addChild(packet)
        
        let followAction = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 1.8)
        followAction.timingMode = .easeInEaseOut
        
        let remove = SKAction.removeFromParent()
        packet.run(SKAction.sequence([followAction, remove]))
    }

    func sendDataPacket(from start: CGPoint, to end: CGPoint, color: SKColor) {
        let path = CGMutablePath()
        path.move(to: start)
        let ctrlX = (start.x + end.x) / 2 + CGFloat.random(in: -40...40)
        let ctrlY = (start.y + end.y) / 2 + CGFloat.random(in: -40...40)
        path.addQuadCurve(to: end, control: CGPoint(x: ctrlX, y: ctrlY))
        
        spawnDataPacket(onPath: path, color: color)
    }

    // MARK: - Location Calculators ─────────────────────────────────────

    private func getPrimaryDeskIndex(for name: String) -> Int? {
        switch name {
        case "Steve": return 0
        case "Jony": return 1
        case "Ada": return 2
        case "Alan": return 3
        case "Linus": return 4
        case "Margaret": return 5
        case "Grace": return 6
        case "Dieter": return 7
        default: return nil
        }
    }
    
    private func getDeskIndex(for name: String) -> Int {
        if let primaryIndex = getPrimaryDeskIndex(for: name) {
            return primaryIndex
        }
        let nonPrimary = pods.keys
            .filter { getPrimaryDeskIndex(for: $0) == nil }
            .sorted()
        let index = nonPrimary.firstIndex(of: name) ?? 0
        return 8 + (index % 12)
    }

    // MARK: - Public API ───────────────────────────────────────────────

    func spawnAgent(name: String, role: String, accentHex: String, index: Int) {
        guard pods[name] == nil else { return }

        let pod = AgentSpriteNode(name: name, role: role, accentHex: accentHex)
        pod.updateTheme(isDark: isDarkTheme)
        pods[name] = pod
        
        let target = layout.deskPosition(index: getDeskIndex(for: name))
        
        pod.homePosition = target
        pod.zPosition = 1

        pod.position = CGPoint(x: target.x, y: size.height + 80)
        pod.alpha = 0
        addChild(pod)

        let dropIn = SKAction.group([
            SKAction.moveTo(y: target.y, duration: 0.55),
            SKAction.fadeIn(withDuration: 0.45)
        ])
        dropIn.timingMode = .easeOut
        pod.run(SKAction.sequence([
            SKAction.wait(forDuration: Double(index) * 0.07),
            dropIn
        ])) { [weak self] in
            self?.relocateIdlePods()
        }
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
        pod.run(depart) { [weak self] in
            self?.relocateIdlePods()
        }
    }

    func setAgentState(_ name: String, state: OfficeAgentState) {
        guard let pod = pods[name] else { return }
        pod.setState(state)

        var newHome = pod.homePosition

        switch state {
        case .idle:
            let index = getDeskIndex(for: name)
            newHome = layout.deskPosition(index: index)
            updateDeskLighting(index: index, active: false)
            updatePostIt(for: name, state: state, color: pod.accentColor)

        case .working, .speaking, .waiting:
            if !isDebateActive {
                let index = getDeskIndex(for: name)
                newHome = layout.deskPosition(index: index)
                updateDeskLighting(index: index, active: true, color: pod.accentColor)
            }
            updatePostIt(for: name, state: state, color: pod.accentColor)
            
            // Spawn data packet on state change activation
            if state == .working {
                let serverCenter = layout.mainframePosition
                sendDataPacket(from: pod.position, to: serverCenter, color: pod.accentColor)
            } else if state == .speaking {
                if isDebateActive {
                    let center = debateCenter
                    sendDataPacket(from: pod.position, to: center, color: pod.accentColor)
                } else {
                    let otherActive = pods.filter { $0.key != name && $0.value.state != .idle }
                    if let target = otherActive.randomElement()?.value {
                        sendDataPacket(from: pod.position, to: target.position, color: pod.accentColor)
                    }
                }
            }

        case .debating:
            let index = getDeskIndex(for: name)
            updateDeskLighting(index: index, active: false)
            updatePostIt(for: name, state: state, color: pod.accentColor)
        }

        pod.homePosition = newHome

        if !pod.isBeingDragged && pod.position != newHome {
            pod.removeAction(forKey: "walk")
            pod.removeAction(forKey: "wobble")

            let dist = hypot(pod.position.x - newHome.x, pod.position.y - newHome.y)
            let dur = max(0.5, Double(dist) / 180.0)

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
                
                if state == .idle {
                    self.relocateIdlePods()
                }
            }

            pod.run(wobble, withKey: "wobble")
            pod.run(SKAction.sequence([walk, completion]), withKey: "walk")
        }
    }

    private func relocateIdlePods() {
        for (name, pod) in pods {
            guard pod.state == .idle && !pod.isBeingDragged else { continue }
            
            let targetPos: CGPoint
            targetPos = layout.deskPosition(index: getDeskIndex(for: name))
            
            if pod.homePosition != targetPos {
                pod.homePosition = targetPos
                
                pod.removeAction(forKey: "walk")
                pod.removeAction(forKey: "wobble")
                
                let walk = SKAction.move(to: targetPos, duration: 0.5)
                walk.timingMode = .easeInEaseOut
                
                let wobble = SKAction.repeatForever(SKAction.sequence([
                    SKAction.rotate(toAngle: 0.06, duration: 0.12),
                    SKAction.rotate(toAngle: -0.06, duration: 0.12)
                ]))
                
                let completion = SKAction.run { [weak pod] in
                    guard let pod = pod else { return }
                    pod.removeAction(forKey: "wobble")
                    pod.zRotation = 0
                    pod.setState(.idle)
                }
                
                pod.run(wobble, withKey: "wobble")
                pod.run(SKAction.sequence([walk, completion]), withKey: "walk")
            }
        }
    }

    func updateTerminalLog(for agentName: String, text: String) {
        pods[agentName]?.updateLogText(text)
    }

    // MARK: - Floaty Speech Bubbles ─────────────────────────────────────
    
    func spawnSpeechBubble(above pod: AgentSpriteNode, text: String) {
        let bubbleKey = "bubble_\(pod.agentName)"
        childNode(withName: bubbleKey)?.removeFromParent()
        
        let bubble = SKNode()
        bubble.name = bubbleKey
        bubble.position = CGPoint(x: pod.position.x, y: pod.position.y + 70)
        bubble.zPosition = 100
        bubble.alpha = 0
        
        let label = SKLabelNode(text: text)
        label.fontName = "SFProText-Semibold"
        label.fontSize = 8.5
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 0)
        
        let textWidth = label.frame.width
        let bubbleW = max(72, textWidth + 16)
        let bubbleH: CGFloat = 20
        
        let bg = SKShapeNode(rectOf: CGSize(width: bubbleW, height: bubbleH), cornerRadius: 6)
        bg.fillColor = SKColor.black.withAlphaComponent(0.85)
        bg.strokeColor = pod.accentColor.withAlphaComponent(0.9)
        bg.lineWidth = 1.2
        
        let pointer = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -5, y: -bubbleH/2))
        path.addLine(to: CGPoint(x: 0, y: -bubbleH/2 - 5))
        path.addLine(to: CGPoint(x: 5, y: -bubbleH/2))
        path.closeSubpath()
        pointer.path = path
        pointer.fillColor = SKColor.black.withAlphaComponent(0.85)
        pointer.strokeColor = pod.accentColor.withAlphaComponent(0.9)
        pointer.lineWidth = 1.2
        
        bubble.addChild(bg)
        bubble.addChild(pointer)
        bubble.addChild(label)
        
        addChild(bubble)
        
        let moveUp = SKAction.moveBy(x: 0, y: 35, duration: 2.2)
        moveUp.timingMode = .easeOut
        
        let fadeIn = SKAction.fadeIn(withDuration: 0.25)
        let fadeOut = SKAction.fadeOut(withDuration: 0.45)
        let delay = SKAction.wait(forDuration: 1.5)
        
        let seq = SKAction.sequence([
            SKAction.group([fadeIn, moveUp]),
            delay,
            fadeOut,
            SKAction.removeFromParent()
        ])
        
        bubble.run(seq)
    }

    // MARK: - Drag & Toss Physics (macOS mouse handlers) ──────────────────

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let touchedNodes = nodes(at: location)

        var clickedPod = false
        for node in touchedNodes {
            var current: SKNode? = node
            while current != nil {
                if let pod = current as? AgentSpriteNode {
                    selectedPodForDrag = pod
                    pod.isBeingDragged = true
                    pod.returnTask?.cancel()

                    pod.physicsBody?.isDynamic = true
                    pod.physicsBody?.affectedByGravity = false
                    pod.physicsBody?.velocity = .zero
                    pod.physicsBody?.angularVelocity = 0

                    pod.startGrabAnimation()

                    lastDragPos = location
                    lastDragTime = event.timestamp
                    clickedPod = true
                    return
                }
                current = current?.parent
            }
        }

        if !clickedPod {
            triggerFloorRipple(at: location)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pod = selectedPodForDrag else { return }
        let location = event.location(in: self)

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

        let velocityMultiplier: CGFloat = 0.05
        let impulse = CGVector(
            dx: dragStartVelocity.x * velocityMultiplier,
            dy: dragStartVelocity.y * velocityMultiplier
        )
        pod.physicsBody?.applyImpulse(impulse)

        triggerReturnHome(for: pod)
    }

    private func triggerReturnHome(for pod: AgentSpriteNode) {
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

        let table = buildDebateTable()
        let center = layout.meetingCenter
        debateCenter = center
        table.position = center
        table.alpha = 0
        table.zPosition = 0
        addChild(table)
        debateTable = table
        table.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.1),
            SKAction.fadeIn(withDuration: 0.7)
        ]))

        for (i, name) in participants.enumerated() {
            guard let pod = pods[name] else { continue }
            let seat = layout.debateSeat(index: i, count: participants.count)

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

        debateTable?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ]))
        debateTable = nil

        for (i, name) in participants.enumerated() {
            guard let pod = pods[name] else { continue }
            
            let home: CGPoint
            home = layout.deskPosition(index: getDeskIndex(for: name))
            
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

    private func emitSpark(from start: CGPoint, to end: CGPoint, color: SKColor) {
        let spark = SKShapeNode(circleOfRadius: 2.5)
        spark.fillColor = color
        spark.strokeColor = color.withAlphaComponent(0.4)
        spark.lineWidth = 1.0
        spark.position = start
        spark.zPosition = 5
        addChild(spark)

        let move = SKAction.move(to: end, duration: 0.45)
        let fade = SKAction.fadeOut(withDuration: 0.45)
        let remove = SKAction.removeFromParent()

        spark.run(SKAction.sequence([
            SKAction.group([move, fade]),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.handleSparkImpact(at: end, color: color)
            },
            remove
        ]))
    }

    private func handleSparkImpact(at point: CGPoint, color: SKColor) {
        if let table = self.debateTable, let beacon = table.childNode(withName: "debate_beacon") as? SKShapeNode {
            let originalColor = SKColor.cyan.withAlphaComponent(0.25)
            let originalStroke = SKColor.cyan.withAlphaComponent(0.7)
            
            beacon.removeAllActions()
            beacon.run(SKAction.sequence([
                SKAction.group([
                    SKAction.run {
                        beacon.fillColor = color.withAlphaComponent(0.55)
                        beacon.strokeColor = color
                    },
                    SKAction.scale(to: 1.8, duration: 0.08)
                ]),
                SKAction.wait(forDuration: 0.12),
                SKAction.group([
                    SKAction.scale(to: 1.0, duration: 0.15),
                    SKAction.run {
                        beacon.fillColor = originalColor
                        beacon.strokeColor = originalStroke
                    }
                ]),
                SKAction.run { [weak beacon] in
                    guard let beacon = beacon else { return }
                    let pulse = SKAction.repeatForever(SKAction.sequence([
                        SKAction.scale(to: 1.5, duration: 1.1),
                        SKAction.scale(to: 1.0, duration: 1.1)
                    ]))
                    beacon.run(pulse)
                }
            ]))
        }

        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 280
        emitter.particleLifetime = 0.45
        emitter.particlePositionRange = CGVector(dx: 4, dy: 4)
        emitter.particleSpeed = 110
        emitter.particleSpeedRange = 50
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2
        emitter.particleScale = 0.08
        emitter.particleScaleRange = 0.04
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -2.2
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        emitter.position = point
        emitter.zPosition = 6
        addChild(emitter)
        
        emitter.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.08),
            SKAction.run { emitter.particleBirthRate = 0 },
            SKAction.wait(forDuration: 0.5),
            SKAction.removeFromParent()
        ]))

        if Double.random(in: 0...1) < 0.42 {
            let words = [
                "💡 Ideia", "🧠 Lógica", "🔥 Argumento", "📊 Dados", "⚡ Síntese",
                "💻 Código", "🎯 Solução", "🧩 Arquitetura", "🛡️ Segurança", "🚀 Performance",
                "📈 Escalabilidade", "💰 Custos", "⏱️ Latência", "🤖 IA", "💎 Inovação",
                "💬 Consenso", "🔄 Iteração", "⚙️ Infra", "📢 Proposta", "📈 Progresso"
            ]
            let word = words.randomElement() ?? "💡 Ideia"
            let label = SKLabelNode(text: word)
            label.fontName = "SFMono-Bold"
            label.fontSize = 9.5
            label.fontColor = color.withAlphaComponent(0.9)
            label.position = CGPoint(x: point.x + CGFloat.random(in: -25...25), y: point.y + CGFloat.random(in: -10...10))
            label.zPosition = 12
            label.alpha = 0
            addChild(label)
            
            let drift = SKAction.moveBy(x: CGFloat.random(in: -35...35), y: CGFloat.random(in: 45...75), duration: 1.3)
            let fadeIn = SKAction.fadeIn(withDuration: 0.25)
            let fadeOut = SKAction.fadeOut(withDuration: 0.65)
            let scale = SKAction.scale(to: 1.15, duration: 1.3)
            let remove = SKAction.removeFromParent()
            
            label.run(SKAction.sequence([
                SKAction.group([fadeIn, drift, scale]),
                fadeOut,
                remove
            ]))
        }
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)

        debateLaserContainer.removeAllChildren()

        // ── Ambient Background Pathway Packets ──────────────────────────
        if currentTime - lastAmbientPacketTime > 0.8 {
            lastAmbientPacketTime = currentTime
            
            let layout = self.layout
            let workCenter = layout.workCenter
            let loungeCenter = layout.loungeCenter
            let meetingCenter = layout.meetingCenter
            let serverCenter = layout.mainframePosition
            
            let choice = Int.random(in: 0...3)
            let path = CGMutablePath()
            let color: SKColor
            
            if choice == 0 {
                path.move(to: workCenter)
                path.addQuadCurve(to: loungeCenter, control: CGPoint(x: size.width / 2, y: size.height - 150))
                color = SKColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 0.25)
            } else if choice == 1 {
                path.move(to: workCenter)
                path.addQuadCurve(to: meetingCenter, control: CGPoint(x: 260, y: 220))
                color = SKColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 0.25)
            } else if choice == 2 {
                path.move(to: workCenter)
                path.addQuadCurve(to: serverCenter, control: CGPoint(x: 100, y: size.height - 350))
                color = SKColor(red: 0.1, green: 0.8, blue: 0.5, alpha: 0.25)
            } else {
                path.move(to: meetingCenter)
                path.addQuadCurve(to: loungeCenter, control: CGPoint(x: size.width - 150, y: 190))
                color = SKColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 0.25)
            }
            
            let packet = SKShapeNode(circleOfRadius: 2.0)
            packet.fillColor = color
            packet.strokeColor = .clear
            packet.zPosition = -7
            addChild(packet)
            
            let followAction = SKAction.follow(path, asOffset: false, orientToPath: false, duration: Double.random(in: 2.2...3.5))
            followAction.timingMode = .easeInEaseOut
            packet.run(SKAction.sequence([
                followAction,
                SKAction.removeFromParent()
            ]))
        }

        // ── Footprints and Warp Dust Trails ─────────────────────────────────
        for (_, pod) in pods {
            if pod.lastPositionForFootprints == .zero {
                pod.lastPositionForFootprints = pod.position
                continue
            }
            
            let dist = hypot(pod.position.x - pod.lastPositionForFootprints.x,
                             pod.position.y - pod.lastPositionForFootprints.y)
            if dist > 8.0 {
                let footprintPos = CGPoint(x: pod.position.x, y: pod.position.y - 45)
                spawnFootprint(at: footprintPos, color: pod.accentColor)
                pod.lastPositionForFootprints = pod.position
            }
        }

        // ── Periodic Data Packet Scheduler ──────────────────────────────────
        if currentTime - lastPacketTime > 1.8 {
            lastPacketTime = currentTime
            let activePods = pods.values.filter { $0.state != .idle }
            if !activePods.isEmpty, let randomPod = activePods.randomElement() {
                let layout = self.layout
                let workCenter = layout.workCenter
                let loungeCenter = layout.loungeCenter
                let meetingCenter = layout.meetingCenter
                let serverCenter = layout.mainframePosition
                
                if isDebateActive {
                    let path = CGMutablePath()
                    path.move(to: randomPod.position)
                    let ctrl = CGPoint(x: (randomPod.position.x + debateCenter.x)/2 + CGFloat.random(in: -30...30),
                                       y: (randomPod.position.y + debateCenter.y)/2 + CGFloat.random(in: -30...30))
                    path.addQuadCurve(to: debateCenter, control: ctrl)
                    spawnDataPacket(onPath: path, color: randomPod.accentColor)
                } else if randomPod.state == .working {
                    let path = CGMutablePath()
                    path.move(to: randomPod.position)
                    let ctrl = CGPoint(x: (randomPod.position.x + serverCenter.x)/2,
                                       y: (randomPod.position.y + serverCenter.y)/2 + 50)
                    path.addQuadCurve(to: serverCenter, control: ctrl)
                    spawnDataPacket(onPath: path, color: randomPod.accentColor)
                } else {
                    let choice = Int.random(in: 0...3)
                    if choice == 0 {
                        let path = CGMutablePath()
                        path.move(to: workCenter)
                        path.addQuadCurve(to: loungeCenter, control: CGPoint(x: size.width / 2, y: size.height - 150))
                        spawnDataPacket(onPath: path, color: SKColor(red: 0.7, green: 0.3, blue: 0.8, alpha: 0.8))
                    } else if choice == 1 {
                        let path = CGMutablePath()
                        path.move(to: workCenter)
                        path.addQuadCurve(to: meetingCenter, control: CGPoint(x: 260, y: 220))
                        spawnDataPacket(onPath: path, color: SKColor(red: 0.0, green: 0.6, blue: 0.8, alpha: 0.8))
                    } else if choice == 2 {
                        let path = CGMutablePath()
                        path.move(to: workCenter)
                        path.addQuadCurve(to: serverCenter, control: CGPoint(x: 100, y: size.height - 350))
                        spawnDataPacket(onPath: path, color: SKColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 0.8))
                    } else {
                        let path = CGMutablePath()
                        path.move(to: meetingCenter)
                        path.addQuadCurve(to: loungeCenter, control: CGPoint(x: size.width - 150, y: 190))
                        spawnDataPacket(onPath: path, color: SKColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 0.8))
                    }
                }
            }
        }

        // ── Debate Laser Streams ────────────────────────────────────────────
        guard isDebateActive else { return }
        let center = debateCenter

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
                    emitSpark(from: pod.position, to: center, color: baseColor)
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

        let outerRing = SKShapeNode(ellipseOf: CGSize(width: 270, height: 170))
        outerRing.fillColor = SKColor.cyan.withAlphaComponent(0.03)
        outerRing.strokeColor = SKColor.cyan.withAlphaComponent(0.15)
        outerRing.lineWidth = 2.0
        container.addChild(outerRing)

        let dial1 = SKShapeNode(ellipseOf: CGSize(width: 240, height: 150))
        dial1.fillColor = .clear
        dial1.strokeColor = SKColor.cyan.withAlphaComponent(0.12)
        dial1.lineWidth = 0.8
        
        let ticksPath = CGMutablePath()
        for i in 0..<24 {
            let angle = CGFloat(i) / 24.0 * 2.0 * .pi
            let start = CGPoint(x: cos(angle) * 114, y: sin(angle) * 71)
            let end = CGPoint(x: cos(angle) * 118, y: sin(angle) * 74)
            ticksPath.move(to: start)
            ticksPath.addLine(to: end)
        }
        let ticksNode = SKShapeNode(path: ticksPath)
        ticksNode.strokeColor = SKColor.cyan.withAlphaComponent(0.15)
        ticksNode.lineWidth = 0.5
        dial1.addChild(ticksNode)
        dial1.run(SKAction.repeatForever(SKAction.rotate(byAngle: -.pi * 2, duration: 20)))
        container.addChild(dial1)

        let dial2 = SKShapeNode(ellipseOf: CGSize(width: 210, height: 132))
        dial2.fillColor = .clear
        dial2.strokeColor = SKColor.cyan.withAlphaComponent(0.08)
        dial2.lineWidth = 1.0
        
        let ticks2Path = CGMutablePath()
        for i in 0..<16 {
            let angle = CGFloat(i) / 16.0 * 2.0 * .pi
            let start = CGPoint(x: cos(angle) * 101, y: sin(angle) * 63)
            let end = CGPoint(x: cos(angle) * 105, y: sin(angle) * 66)
            ticks2Path.move(to: start)
            ticks2Path.addLine(to: end)
        }
        let ticks2Node = SKShapeNode(path: ticks2Path)
        ticks2Node.strokeColor = SKColor.cyan.withAlphaComponent(0.12)
        ticks2Node.lineWidth = 0.5
        dial2.addChild(ticks2Node)
        dial2.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 15)))
        container.addChild(dial2)

        let sweepPath = CGMutablePath()
        sweepPath.move(to: .zero)
        sweepPath.addArc(center: .zero, radius: 120, startAngle: 0, endAngle: .pi / 8, clockwise: false)
        sweepPath.addLine(to: .zero)
        sweepPath.closeSubpath()
        
        let radarSweep = SKShapeNode(path: sweepPath)
        radarSweep.fillColor = SKColor.cyan.withAlphaComponent(0.03)
        radarSweep.strokeColor = SKColor.cyan.withAlphaComponent(0.06)
        radarSweep.lineWidth = 0.5
        radarSweep.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 6.0)))
        container.addChild(radarSweep)

        for angleDeg in [0, 90, 180, 270] {
            let angleRad = CGFloat(angleDeg) * .pi / 180.0
            let label = SKLabelNode(text: "\(angleDeg)°")
            label.fontName = "SFMono-Regular"
            label.fontSize = 6
            label.fontColor = SKColor.cyan.withAlphaComponent(0.3)
            label.position = CGPoint(x: cos(angleRad) * 142, y: sin(angleRad) * 90 - 2)
            container.addChild(label)
        }

        let beacon = SKShapeNode(circleOfRadius: 10)
        beacon.name = "debate_beacon"
        beacon.fillColor = SKColor.cyan.withAlphaComponent(0.25)
        beacon.strokeColor = SKColor.cyan.withAlphaComponent(0.7)
        beacon.lineWidth = 1
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 1.1),
            SKAction.scale(to: 1.0, duration: 1.1)
        ]))
        beacon.run(pulse)
        container.addChild(beacon)

        let orbit = SKShapeNode(circleOfRadius: 38)
        orbit.fillColor = .clear
        orbit.strokeColor = SKColor.cyan.withAlphaComponent(0.2)
        orbit.lineWidth = 1
        orbit.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 8)))
        container.addChild(orbit)

        let label = SKLabelNode(text: "⚔ WAR ROOM ⚔")
        label.fontName  = "SFMono-Regular"
        label.fontSize  = 10
        label.fontColor = SKColor.cyan.withAlphaComponent(0.35)
        label.position  = CGPoint(x: 0, y: -7)
        container.addChild(label)

        return container
    }

    private func setupMainframe() {
        childNode(withName: "mainframe_crop")?.removeFromParent()
        addChild(OfficePropFactory.makeMainframe(at: layout.mainframePosition))
    }

    func updateTheme(isDark: Bool) {
        self.isDarkTheme = isDark

        // Update floor background — transparent tint, not opaque
        if let floor = childNode(withName: "floor_background") as? SKShapeNode {
            floor.fillColor = isDark
                ? SKColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 0.35)
                : SKColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 0.15)
        }

        // Update gridlines
        if let grid = childNode(withName: "grid_layer") {
            let gc = isDark
                ? SKColor(white: 1.0, alpha: 0.03)
                : SKColor(white: 0.0, alpha: 0.04)
            for child in grid.children {
                if let line = child as? SKShapeNode {
                    line.fillColor = gc
                }
            }
        }

        // Update lounge area colors
        if let loungeFloor = childNode(withName: "lounge_floor") as? SKShapeNode {
            loungeFloor.fillColor = isDark
                ? SKColor(red: 0.08, green: 0.06, blue: 0.12, alpha: 0.3)
                : SKColor(red: 0.90, green: 0.88, blue: 0.95, alpha: 0.2)
        }

        if let lounge = childNode(withName: "lounge_bg") as? SKShapeNode {
            if isDark {
                lounge.fillColor = SKColor(red: 0.12, green: 0.08, blue: 0.16, alpha: 0.15)
                lounge.strokeColor = SKColor(red: 0.6, green: 0.3, blue: 0.7, alpha: 0.10)
            } else {
                lounge.fillColor = SKColor(red: 0.95, green: 0.92, blue: 0.98, alpha: 0.15)
                lounge.strokeColor = SKColor(red: 0.6, green: 0.3, blue: 0.7, alpha: 0.15)
            }

            if let label = lounge.childNode(withName: "lounge_lbl") as? SKLabelNode {
                label.fontColor = isDark
                    ? SKColor(red: 0.7, green: 0.4, blue: 0.8, alpha: 0.35)
                    : SKColor(red: 0.5, green: 0.2, blue: 0.6, alpha: 0.7)
            }
        }

        // Update work zone label
        if let zoneLabel = childNode(withName: "zone_label") as? SKLabelNode {
            zoneLabel.fontColor = isDark
                ? SKColor.cyan.withAlphaComponent(0.12)
                : SKColor.blue.withAlphaComponent(0.25)
        }

        // Update watermark
        if let watermark = childNode(withName: "watermark_label") as? SKLabelNode {
            watermark.fontColor = isDark
                ? SKColor.white.withAlphaComponent(0.04)
                : SKColor.black.withAlphaComponent(0.06)
        }

        // Update all active/idle pods
        for (_, pod) in pods {
            pod.updateTheme(isDark: isDark)
        }
    }

    private func setupWhiteboard() {
        childNode(withName: "scrum_board")?.removeFromParent()
        addChild(OfficePropFactory.makeStandupBoard(at: layout.boardPosition))
    }

    private func updatePostIt(for name: String, state: OfficeAgentState, color: SKColor) {
        guard let board = childNode(withName: "scrum_board") else { return }
        
        let postItName = "postit_\(name.lowercased())"
        board.childNode(withName: postItName)?.removeFromParent()
        
        let colIndex: Int
        switch state {
        case .waiting:
            colIndex = 0 // TODO
        case .working, .speaking:
            colIndex = 1 // DOING
        case .idle:
            colIndex = 2 // DONE
        case .debating:
            return
        }
        
        let boardW: CGFloat = 180
        let colW = boardW / 3
        let targetX = -boardW/2 + CGFloat(colIndex)*colW + colW/2
        
        let postIt = SKShapeNode(rectOf: CGSize(width: 24, height: 16), cornerRadius: 2)
        postIt.name = postItName
        postIt.fillColor = color.withAlphaComponent(0.75)
        postIt.strokeColor = .white.withAlphaComponent(0.3)
        postIt.lineWidth = 0.5
        postIt.zPosition = 1
        
        let lbl = SKLabelNode(text: String(name.prefix(3)).uppercased())
        lbl.fontName = "SFMono-Bold"
        lbl.fontSize = 6.5
        lbl.fontColor = .black
        lbl.verticalAlignmentMode = .center
        postIt.addChild(lbl)
        
        let targetY = CGFloat.random(in: -40...20)
        postIt.position = CGPoint(x: targetX, y: targetY)
        postIt.alpha = 0
        board.addChild(postIt)
        
        if colIndex == 2 {
            postIt.run(SKAction.sequence([
                SKAction.fadeIn(withDuration: 0.3),
                SKAction.wait(forDuration: 3.5),
                SKAction.fadeOut(withDuration: 0.5),
                SKAction.removeFromParent()
            ]))
        } else {
            postIt.run(SKAction.fadeIn(withDuration: 0.3))
        }
    }

    private func updateDeskLighting(index: Int, active: Bool, color: SKColor = .cyan) {
        guard let desk = childNode(withName: "desk_\(index)") else { return }
        guard let screen = desk.childNode(withName: "screen") as? SKShapeNode else { return }
        
        screen.removeAction(forKey: "screen_pulse")
        screen.alpha = 1.0
        
        if active {
            screen.fillColor = color.withAlphaComponent(0.35)
            screen.strokeColor = .clear
            let pulse = SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 1.0, duration: 0.5),
                SKAction.fadeAlpha(to: 0.4, duration: 0.5)
            ]))
            screen.run(pulse, withKey: "screen_pulse")
            
            // Also light up second screen
            if let screen2 = desk.childNode(withName: "screen2") as? SKShapeNode {
                screen2.fillColor = color.withAlphaComponent(0.25)
                screen2.run(pulse.copy() as! SKAction, withKey: "screen_pulse")
            }
        } else {
            screen.fillColor = SKColor.cyan.withAlphaComponent(0.06)
            screen.strokeColor = .clear
            if let screen2 = desk.childNode(withName: "screen2") as? SKShapeNode {
                screen2.removeAction(forKey: "screen_pulse")
                screen2.fillColor = SKColor.cyan.withAlphaComponent(0.06)
            }
        }
    }
}
