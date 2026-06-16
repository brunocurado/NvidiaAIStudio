import SpriteKit

enum OfficePropFactory {
    static func cornerBracketsPath(rect: CGRect, cornerRadius: CGFloat, bracketLength: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        path.move(to: CGPoint(x: minX, y: maxY - bracketLength))
        path.addLine(to: CGPoint(x: minX, y: maxY - cornerRadius))
        path.addArc(center: CGPoint(x: minX + cornerRadius, y: maxY - cornerRadius), radius: cornerRadius, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: minX + bracketLength, y: maxY))

        path.move(to: CGPoint(x: maxX - bracketLength, y: maxY))
        path.addLine(to: CGPoint(x: maxX - cornerRadius, y: maxY))
        path.addArc(center: CGPoint(x: maxX - cornerRadius, y: maxY - cornerRadius), radius: cornerRadius, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: maxX, y: maxY - bracketLength))

        path.move(to: CGPoint(x: maxX, y: minY + bracketLength))
        path.addLine(to: CGPoint(x: maxX, y: minY + cornerRadius))
        path.addArc(center: CGPoint(x: maxX - cornerRadius, y: minY + cornerRadius), radius: cornerRadius, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: maxX - bracketLength, y: minY))

        path.move(to: CGPoint(x: minX + bracketLength, y: minY))
        path.addLine(to: CGPoint(x: minX + cornerRadius, y: minY))
        path.addArc(center: CGPoint(x: minX + cornerRadius, y: minY + cornerRadius), radius: cornerRadius, startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
        path.addLine(to: CGPoint(x: minX, y: minY + bracketLength))

        return path
    }

    static func makeDeskSet(index: Int) -> (shadow: SKShapeNode, desk: SKShapeNode, chair: SKShapeNode) {
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 110, height: 40))
        shadow.name = "desk_shadow_\(index)"
        shadow.fillColor = SKColor.black.withAlphaComponent(0.12)
        shadow.strokeColor = .clear
        shadow.zPosition = -6

        let desk = SKShapeNode(rectOf: CGSize(width: 118, height: 46), cornerRadius: 6)
        desk.name = "desk_\(index)"
        desk.fillColor = SKColor(red: 0.50, green: 0.34, blue: 0.20, alpha: 1.0)
        desk.strokeColor = SKColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 0.8)
        desk.lineWidth = 1.2
        desk.zPosition = -5

        let screen1 = SKShapeNode(rectOf: CGSize(width: 22, height: 14), cornerRadius: 2.5)
        screen1.name = "screen"
        screen1.fillColor = SKColor.cyan.withAlphaComponent(0.06)
        screen1.strokeColor = SKColor.cyan.withAlphaComponent(0.22)
        screen1.position = CGPoint(x: -18, y: 10)
        screen1.zPosition = 1
        desk.addChild(screen1)

        let screen2 = SKShapeNode(rectOf: CGSize(width: 22, height: 14), cornerRadius: 2.5)
        screen2.name = "screen2"
        screen2.fillColor = SKColor.cyan.withAlphaComponent(0.06)
        screen2.strokeColor = SKColor.cyan.withAlphaComponent(0.16)
        screen2.position = CGPoint(x: 16, y: 10)
        screen2.zPosition = 1
        desk.addChild(screen2)

        let chair = SKShapeNode(rectOf: CGSize(width: 38, height: 34), cornerRadius: 6)
        chair.name = "chair_\(index)"
        chair.fillColor = SKColor(red: 0.22, green: 0.24, blue: 0.34, alpha: 0.95)
        chair.strokeColor = SKColor.black.withAlphaComponent(0.18)
        chair.lineWidth = 1
        chair.zPosition = -4

        return (shadow, desk, chair)
    }

    static func makeFloorTexture(size: CGSize, isDarkTheme: Bool) -> SKNode {
        let container = SKNode()
        container.name = "floor_texture_container"
        container.zPosition = -10

        let base = SKShapeNode(rectOf: size)
        base.fillColor = isDarkTheme
            ? SKColor(red: 0.34, green: 0.24, blue: 0.15, alpha: 0.78)
            : SKColor(red: 0.76, green: 0.61, blue: 0.43, alpha: 0.78)
        base.strokeColor = .clear
        base.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.addChild(base)

        let plankPath = CGMutablePath()
        let plankH: CGFloat = 42
        var y: CGFloat = 0
        var row = 0
        while y <= size.height + plankH {
            plankPath.move(to: CGPoint(x: 0, y: y))
            plankPath.addLine(to: CGPoint(x: size.width, y: y))

            let offset: CGFloat = row.isMultiple(of: 2) ? 0 : 92
            var x = -offset
            while x <= size.width + 180 {
                plankPath.move(to: CGPoint(x: x, y: y))
                plankPath.addLine(to: CGPoint(x: x, y: y + plankH))
                x += 185
            }
            y += plankH
            row += 1
        }
        let planks = SKShapeNode(path: plankPath)
        planks.strokeColor = isDarkTheme
            ? SKColor.black.withAlphaComponent(0.22)
            : SKColor(red: 0.38, green: 0.24, blue: 0.13, alpha: 0.18)
        planks.lineWidth = 1
        container.addChild(planks)

        let grainPath = CGMutablePath()
        var gy: CGFloat = 16
        while gy < size.height {
            var gx: CGFloat = 28
            while gx < size.width {
                grainPath.move(to: CGPoint(x: gx, y: gy))
                grainPath.addQuadCurve(
                    to: CGPoint(x: gx + 78, y: gy + CGFloat.random(in: -4...4)),
                    control: CGPoint(x: gx + 38, y: gy + CGFloat.random(in: -8...8))
                )
                gx += 150
            }
            gy += 32
        }
        let grain = SKShapeNode(path: grainPath)
        grain.strokeColor = SKColor.black.withAlphaComponent(isDarkTheme ? 0.09 : 0.06)
        grain.lineWidth = 0.7
        container.addChild(grain)

        return container
    }

    static func makeMainframe(at position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position
        container.zPosition = -5
        container.name = "mainframe_crop"

        let rack = SKShapeNode(rectOf: CGSize(width: 66, height: 112), cornerRadius: 9)
        rack.name = "mainframe"
        rack.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 0.96)
        rack.strokeColor = SKColor.cyan.withAlphaComponent(0.34)
        rack.lineWidth = 1.2
        container.addChild(rack)

        for slot in 0..<7 {
            let tray = SKShapeNode(rectOf: CGSize(width: 52, height: 8), cornerRadius: 2)
            tray.fillColor = SKColor(white: 0.10, alpha: 0.92)
            tray.strokeColor = SKColor(white: 1, alpha: 0.06)
            tray.lineWidth = 0.5
            tray.position = CGPoint(x: 0, y: 39 - CGFloat(slot) * 12)
            tray.zPosition = 1
            rack.addChild(tray)
        }

        for i in 0..<3 {
            let led = SKShapeNode(circleOfRadius: 2)
            led.fillColor = i == 0 ? .green : .cyan
            led.strokeColor = .clear
            led.position = CGPoint(x: 22, y: CGFloat(35 - i * 12))
            led.zPosition = 1
            rack.addChild(led)

            led.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: Double.random(in: 0.3...1.2)),
                SKAction.fadeAlpha(to: 0.3, duration: 0.15),
                SKAction.fadeAlpha(to: 1.0, duration: 0.15),
            ])))
        }

        let fanNode = SKNode()
        fanNode.position = CGPoint(x: -18, y: -20)
        fanNode.zPosition = 2
        rack.addChild(fanNode)

        let fanOuter = SKShapeNode(circleOfRadius: 8)
        fanOuter.fillColor = .clear
        fanOuter.strokeColor = SKColor(white: 1, alpha: 0.15)
        fanOuter.lineWidth = 0.8
        fanNode.addChild(fanOuter)

        let bladesPath = CGMutablePath()
        for i in 0..<3 {
            let angle = CGFloat(i) / 3.0 * 2.0 * .pi
            bladesPath.move(to: .zero)
            bladesPath.addLine(to: CGPoint(x: cos(angle) * 7.5, y: sin(angle) * 7.5))
        }
        let blades = SKShapeNode(path: bladesPath)
        blades.strokeColor = SKColor.cyan.withAlphaComponent(0.6)
        blades.lineWidth = 1.8
        fanNode.addChild(blades)
        blades.run(SKAction.repeatForever(SKAction.rotate(byAngle: -.pi * 2, duration: 0.4)))

        for j in 0..<2 {
            let meterBg = SKShapeNode(rectOf: CGSize(width: 3.5, height: 35), cornerRadius: 0.8)
            meterBg.fillColor = SKColor.black.withAlphaComponent(0.4)
            meterBg.strokeColor = SKColor.cyan.withAlphaComponent(0.12)
            meterBg.lineWidth = 0.5
            meterBg.position = CGPoint(x: -8 + CGFloat(j) * 7, y: 15)
            meterBg.zPosition = 2
            rack.addChild(meterBg)

            let meterFill = SKShapeNode(rectOf: CGSize(width: 2.5, height: 33), cornerRadius: 0.5)
            meterFill.fillColor = SKColor.green.withAlphaComponent(0.7)
            meterFill.strokeColor = .clear
            meterFill.zPosition = 1
            meterBg.addChild(meterFill)

            meterFill.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scaleY(to: CGFloat.random(in: 0.25...0.95), duration: Double.random(in: 0.4...0.9)),
                SKAction.scaleY(to: CGFloat.random(in: 0.35...1.0), duration: Double.random(in: 0.3...0.8))
            ])))
        }

        let rackLabel = SKLabelNode(text: "MAINFRAME")
        rackLabel.fontName = "SFMono-Regular"
        rackLabel.fontSize = 6
        rackLabel.fontColor = SKColor(red: 0.3, green: 0.5, blue: 0.6, alpha: 0.35)
        rackLabel.position = CGPoint(x: 0, y: -62)
        rack.addChild(rackLabel)

        return container
    }

    static func makeLoungeShell(isDarkTheme: Bool) -> (floor: SKShapeNode, panel: SKShapeNode) {
        let floor = SKShapeNode()
        floor.name = "lounge_floor"
        floor.fillColor = isDarkTheme
            ? SKColor(red: 0.14, green: 0.12, blue: 0.16, alpha: 0.28)
            : SKColor(red: 0.90, green: 0.86, blue: 0.79, alpha: 0.30)
        floor.strokeColor = .clear
        floor.zPosition = -7

        let panel = SKShapeNode()
        panel.name = "lounge_bg"
        panel.fillColor = isDarkTheme
            ? SKColor(red: 0.12, green: 0.08, blue: 0.13, alpha: 0.22)
            : SKColor(red: 0.92, green: 0.86, blue: 0.78, alpha: 0.24)
        panel.strokeColor = SKColor(red: 0.6, green: 0.3, blue: 0.7, alpha: 0.16)
        panel.lineWidth = 1.2
        panel.zPosition = -6

        let loungeLabel = SKLabelNode(text: "STANDBY")
        loungeLabel.name = "lounge_lbl"
        loungeLabel.fontName = "SFMono-Bold"
        loungeLabel.fontSize = 8
        loungeLabel.fontColor = SKColor(red: 0.9, green: 0.6, blue: 0.9, alpha: 0.55)
        panel.addChild(loungeLabel)

        for i in 0..<3 {
            let cushion = SKShapeNode(rectOf: CGSize(width: 54, height: 22), cornerRadius: 7)
            cushion.name = "lounge_seat_\(i)"
            cushion.fillColor = SKColor(red: 0.33, green: 0.24, blue: 0.34, alpha: 0.95)
            cushion.strokeColor = SKColor.black.withAlphaComponent(0.18)
            cushion.lineWidth = 1
            cushion.zPosition = 1
            panel.addChild(cushion)
        }

        let steamEmitter = SKEmitterNode()
        steamEmitter.name = "lounge_steam"
        steamEmitter.particleBirthRate = 2
        steamEmitter.particleLifetime = 5.0
        steamEmitter.particleSpeed = 6
        steamEmitter.particleSpeedRange = 3
        steamEmitter.emissionAngle = .pi / 2
        steamEmitter.particleScale = 0.06
        steamEmitter.particleScaleRange = 0.04
        steamEmitter.particleAlpha = 0.08
        steamEmitter.particleAlphaSpeed = -0.02
        steamEmitter.particleColor = SKColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1.0)
        panel.addChild(steamEmitter)

        return (floor, panel)
    }

    static func makeStandupBoard(at position: CGPoint) -> SKShapeNode {
        let boardW: CGFloat = 180
        let boardH: CGFloat = 120
        let board = SKShapeNode(rectOf: CGSize(width: boardW, height: boardH), cornerRadius: 8)
        board.name = "scrum_board"
        board.fillColor = SKColor(white: 0.93, alpha: 0.88)
        board.strokeColor = SKColor(white: 0.10, alpha: 0.35)
        board.lineWidth = 1.2
        board.position = position
        board.zPosition = -6

        let title = SKLabelNode(text: "STANDUP BOARD")
        title.fontName = "SFMono-Bold"
        title.fontSize = 8
        title.fontColor = SKColor(white: 0.10, alpha: 0.65)
        title.position = CGPoint(x: 0, y: 45)
        board.addChild(title)

        for i in 0..<3 {
            let x = -boardW / 3 + CGFloat(i) * boardW / 3
            let divider = SKShapeNode(rectOf: CGSize(width: 1, height: 80))
            divider.fillColor = SKColor(white: 0.12, alpha: 0.18)
            divider.strokeColor = .clear
            divider.position = CGPoint(x: x + boardW / 6, y: -6)
            board.addChild(divider)

            let label = SKLabelNode(text: ["WAIT", "DOING", "DONE"][i])
            label.fontName = "SFMono-Regular"
            label.fontSize = 6.5
            label.fontColor = SKColor(white: 0.12, alpha: 0.48)
            label.position = CGPoint(x: -boardW / 3 + CGFloat(i) * boardW / 3 + boardW / 6, y: 29)
            board.addChild(label)
        }

        let sketch = SKShapeNode()
        let sketchPath = CGMutablePath()
        sketchPath.move(to: CGPoint(x: -70, y: -34))
        sketchPath.addLine(to: CGPoint(x: -24, y: -12))
        sketchPath.addLine(to: CGPoint(x: 20, y: -28))
        sketchPath.addLine(to: CGPoint(x: 68, y: -5))
        sketch.path = sketchPath
        sketch.strokeColor = SKColor(red: 0.05, green: 0.20, blue: 0.38, alpha: 0.30)
        sketch.lineWidth = 1.4
        board.addChild(sketch)

        return board
    }
}
