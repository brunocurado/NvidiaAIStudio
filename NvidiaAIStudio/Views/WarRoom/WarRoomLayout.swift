import SpriteKit

struct WarRoomLayout {
    let size: CGSize

    var loungeSize: CGSize {
        CGSize(width: 230, height: 118)
    }

    var loungeCenter: CGPoint {
        CGPoint(x: max(180, min(size.width - 170, 210)), y: 125)
    }

    var meetingCenter: CGPoint {
        CGPoint(x: max(size.width - 430, size.width * 0.72), y: 260)
    }

    var mainframePosition: CGPoint {
        CGPoint(x: 92, y: 120)
    }

    var workRect: CGRect {
        CGRect(
            x: 76,
            y: max(300, size.height - 620),
            width: min(size.width - 560, 1440),
            height: 500
        )
    }

    var workCenter: CGPoint {
        CGPoint(x: min(450, size.width * 0.36), y: max(310, size.height - 285))
    }

    var boardPosition: CGPoint {
        CGPoint(
            x: min(size.width - 480, max(760, workRect.maxX - 180)),
            y: size.height - 185
        )
    }

    var backWallFrame: CGRect {
        CGRect(x: -(size.width - 210) / 2, y: -46, width: size.width - 210, height: 92)
    }

    var backWallPosition: CGPoint {
        CGPoint(x: size.width / 2, y: size.height - 58)
    }

    var headerPosition: CGPoint {
        CGPoint(x: size.width / 2, y: size.height - 42)
    }

    func deskPosition(index: Int) -> CGPoint {
        let col = index % 5
        let row = index / 5
        let availableWidth = max(760, min(size.width - 620, 1320))
        let spacingX = availableWidth / 5
        let spacingY: CGFloat = 128
        let startX: CGFloat = 160
        let startY: CGFloat = max(560, size.height - 330)
        let stagger = row.isMultiple(of: 2) ? CGFloat(0) : spacingX * 0.42

        return CGPoint(
            x: startX + CGFloat(col) * spacingX + stagger,
            y: startY - CGFloat(row) * spacingY
        )
    }

    func debateSeat(index: Int, count: Int, radius: CGFloat = 120) -> CGPoint {
        let angle = CGFloat(index) / CGFloat(max(count, 1)) * 2 * .pi - .pi / 2
        return CGPoint(
            x: meetingCenter.x + cos(angle) * radius,
            y: meetingCenter.y + sin(angle) * (radius * 0.62)
        )
    }
}
