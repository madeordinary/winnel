import AppKit
import Foundation
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for logical in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = logical * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ratio = CGFloat(side) / 1024
        let transform = AffineTransform(scale: ratio); (transform as NSAffineTransform).concat()
        NSColor(calibratedRed: 0.73, green: 0.35, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(roundedRect: .init(x: 32,y: 32,width: 960,height: 960), xRadius: 218,yRadius: 218).fill()
        for (index, offset) in [100.0, 50.0, 0.0].enumerated() {
            NSColor(calibratedWhite: 1, alpha: [0.35, 0.55, 1.0][index]).setFill()
            NSBezierPath(roundedRect: .init(x: 238 + offset,y: 248 + offset,width: 470,height: 480),xRadius: 46,yRadius: 46).fill()
        }
        NSColor(calibratedRed: 0.73,green: 0.35,blue: 0.24,alpha: 1).setFill()
        NSBezierPath(roundedRect: .init(x: 310,y: 586,width: 274,height: 26),xRadius: 13,yRadius: 13).fill()
        NSBezierPath(roundedRect: .init(x: 310,y: 510,width: 210,height: 26),xRadius: 13,yRadius: 13).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(logical)x\(logical)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    }
}
