import AppKit

@MainActor
enum DeskAnchorIcon {
    static func appIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func menuBarIcon(size: CGFloat) -> NSImage {
        let image = appIcon(size: size)
        image.isTemplate = false
        return image
    }

    static func draw(in rect: NSRect) {
        let cornerRadius = rect.width * 0.25
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        backgroundPath.addClip()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.98, alpha: 1.0),
            NSColor(calibratedRed: 0.35, green: 0.38, blue: 1.0, alpha: 1.0)
        ])
        gradient?.draw(in: rect, angle: 315)
        NSGraphicsContext.restoreGraphicsState()

        drawWindows(in: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.25))
    }

    private static func drawWindows(in rect: NSRect) {
        NSColor.white.set()

        let lineWidth = max(2, rect.width * 0.08)
        let back = NSBezierPath(roundedRect: NSRect(
            x: rect.minX,
            y: rect.midY - rect.height * 0.18,
            width: rect.width * 0.56,
            height: rect.height * 0.48
        ), xRadius: lineWidth, yRadius: lineWidth)
        back.lineWidth = lineWidth
        back.stroke()

        let frontRect = NSRect(
            x: rect.minX + rect.width * 0.34,
            y: rect.minY,
            width: rect.width * 0.66,
            height: rect.height * 0.58
        )
        let front = NSBezierPath(roundedRect: frontRect, xRadius: lineWidth, yRadius: lineWidth)
        front.lineWidth = lineWidth
        front.stroke()

        let dotRadius = lineWidth * 0.42
        let dotY = frontRect.maxY - lineWidth * 1.55
        for offset in [0.50, 0.64, 0.78] {
            let centerX = frontRect.minX + frontRect.width * offset
            NSBezierPath(ovalIn: NSRect(
                x: centerX - dotRadius,
                y: dotY - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )).fill()
        }
    }
}
