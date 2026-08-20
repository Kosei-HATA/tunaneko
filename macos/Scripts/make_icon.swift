import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Simple line-art fish: ellipse body + triangle tail + eye, stroke only.
func render(size: Int, path: String) {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

    // dark rounded-square background
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    ctx.setFillColor(CGColor(red: 0.07, green: 0.10, blue: 0.18, alpha: 1))
    ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
    ctx.fillPath()

    ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
    ctx.setLineWidth(s * 0.030)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // body: ellipse
    ctx.strokeEllipse(in: CGRect(x: s * 0.20, y: s * 0.36, width: s * 0.44, height: s * 0.28))

    // tail: triangle attached to the right of the body
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: s * 0.63, y: s * 0.50))
    tail.addLine(to: CGPoint(x: s * 0.82, y: s * 0.64))
    tail.addLine(to: CGPoint(x: s * 0.82, y: s * 0.36))
    tail.closeSubpath()
    ctx.addPath(tail)
    ctx.strokePath()

    // eye: small filled dot near the head
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: s * 0.29, y: s * 0.53, width: s * 0.05, height: s * 0.05))

    // two bubbles above the mouth
    ctx.setLineWidth(s * 0.020)
    ctx.strokeEllipse(in: CGRect(x: s * 0.16, y: s * 0.68, width: s * 0.045, height: s * 0.045))
    ctx.strokeEllipse(in: CGRect(x: s * 0.23, y: s * 0.76, width: s * 0.03, height: s * 0.03))

    guard let img = ctx.makeImage() else { return }
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

guard CommandLine.arguments.count > 1 else {
    print("usage: make_icon.swift <iconset-dir>")
    exit(1)
}
let iconset = CommandLine.arguments[1]
let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in specs {
    render(size: px, path: "\(iconset)/\(name)")
}
print("iconset rendered")
