import Foundation
import CoreGraphics
import ImageIO
import PetCore

public final class SpriteLibrary {
    public struct Frame {
        public let image: CGImage
        let hitMask: [UInt8]
        public func contains(x: Double, y: Double) -> Bool {
            guard x >= 0, x < 1, y >= 0, y < 1 else { return false }
            return hitMask[Int(y * 80) * 80 + Int(x * 80)] > 0
        }
    }
    public private(set) var frames: [DuckState: [Frame]] = [:]
    public private(set) var failure: String?
    public let frameCounts: [DuckState: Int]

    public init(directory: URL? = nil) {
        // Resolve without Bundle.module's fatalError so an absent bundle also falls back.
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        let candidates = bases.map { $0.appendingPathComponent("WatercolorDuck_PetAssets.bundle/Duck") }
        let root = directory ?? candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? bases[0].appendingPathComponent("missing-duck-resources")
        var counts: [DuckState: Int] = [.look:23,.alternateLook:25,.sitDown:20,.standUp:20,.sitting:20]
        do {
            let manifest = try JSONDecoder().decode(SpriteManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
            guard manifest.isValid else { throw AssetError.invalidManifest }
            counts = Dictionary(uniqueKeysWithValues: manifest.clips.map { ($0.state, $0.frames.count) })
            for clip in manifest.clips {
                var loaded: [Frame] = []
                for frame in clip.frames {
                    let url = root.appendingPathComponent(frame.resource)
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                          image.width == 320, image.height == 320 else { throw AssetError.invalidFrame(frame.resource) }
                    var pixels = [UInt8](repeating: 0, count: 80 * 80 * 4)
                    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
                        guard let context = CGContext(data: bytes.baseAddress, width: 80, height: 80,
                            bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                        context.draw(image, in: CGRect(x: 0, y: 0, width: 80, height: 80)); return true
                    }
                    guard rendered else { throw AssetError.invalidFrame(frame.resource) }
                    let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
                    // Dilate by one mask pixel for thin legs and sparse watercolor edges.
                    var mask = alpha
                    for y in 0..<80 { for x in 0..<80 where alpha[y*80+x] > 20 {
                        for yy in max(0,y-1)...min(79,y+1) { for xx in max(0,x-1)...min(79,x+1) { mask[yy*80+xx] = 255 } }
                    } }
                    loaded.append(Frame(image: image, hitMask: mask))
                }
                frames[clip.state] = loaded
            }
        } catch {
            frames.removeAll(); failure = "Sprite loading failed: \(error)"
            NSLog("%@ — using visible square fallback", failure!)
        }
        frameCounts = counts
    }
    public func frame(state: DuckState, index: Int) -> Frame? {
        guard let clip = frames[state], clip.indices.contains(index) else { return nil }
        return clip[index]
    }
    private enum AssetError: Error { case invalidManifest, invalidFrame(String) }
}
