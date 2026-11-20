import Foundation
import CoreGraphics
import ImageIO
import PetCore

public final class SpriteLibrary {
    public struct Frame {
        public let image: CGImage
        /// In the square duck viewport, with AppKit's bottom-left origin.
        public let placement: CGRect
        let hitMask: [UInt8]
        public let occupiedBounds: CGRect
        public func contains(x: Double, y: Double) -> Bool {
            guard x >= 0, x < 1, y >= 0, y < 1 else { return false }
            // Bitmap rows run downward; the native view's coordinates run upward.
            return hitMask[(79 - Int(y * 80)) * 80 + Int(x * 80)] > 0
        }
    }
    public private(set) var frames: [DuckState: [Frame]] = [:]
    public private(set) var speechFrames: [CGImage] = []
    public private(set) var failure: String?
    public private(set) var missingStates = Set<DuckState>()
    public let frameCounts: [DuckState: Int]
    public static let viewportScale = 2.6

    public init(directory: URL? = nil) {
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        let candidates = bases.flatMap { base in
            ["sombrero_PetAssets.bundle/FinalDuck", "sombrero_PetAssets.bundle/Contents/Resources/FinalDuck"].map { base.appendingPathComponent($0) }
        }
        let root = directory ?? candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? bases[0].appendingPathComponent("missing-duck-resources")
        var counts = Dictionary(uniqueKeysWithValues: DuckState.allCases.filter { $0 != .timeout }.map { ($0, 10) })
        do {
            let manifest = try JSONDecoder().decode(SpriteManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
            guard manifest.isValid else { throw AssetError.invalidManifest }
            let side = Double(max(manifest.canvasWidth, manifest.canvasHeight))
            let insetX = (side - Double(manifest.canvasWidth)) / 2
            let insetY = (side - Double(manifest.canvasHeight)) / 2
            for clip in manifest.clips {
                counts[clip.state] = max(10 * (clip.frames.isEmpty ? 1 : 0), clip.frames.count)
                if clip.frames.isEmpty { missingStates.insert(clip.state); continue }
                var loaded: [Frame] = []
                for frame in clip.frames {
                    let image = try Self.load(root.appendingPathComponent(frame.resource))
                    let width = Double(image.width) * clip.scale
                    let height = Double(image.height) * clip.scale
                    let placement = CGRect(x: (insetX + clip.offsetX) / side,
                        y: (insetY + Double(manifest.canvasHeight) - clip.offsetY - height) / side,
                        width: width / side, height: height / side)
                    var pixels = [UInt8](repeating: 0, count: 80 * 80 * 4)
                    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
                        guard let context = CGContext(data: bytes.baseAddress, width: 80, height: 80,
                            bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                        context.draw(image, in: CGRect(x: placement.minX * 80, y: placement.minY * 80,
                            width: placement.width * 80, height: placement.height * 80))
                        return true
                    }
                    guard rendered else { throw AssetError.invalidFrame(frame.resource) }
                    let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
                    var mask = alpha.map { $0 > 20 ? UInt8(255) : 0 }
                    for y in 0..<80 { for x in 0..<80 where alpha[y * 80 + x] > 20 {
                        for yy in max(0, y-2)...min(79, y+2) { for xx in max(0, x-2)...min(79, x+2) { mask[yy*80+xx] = 255 } }
                    } }
                    let occupied = mask.indices.filter { mask[$0] > 0 }
                    let minX = occupied.map { $0 % 80 }.min() ?? 0, maxX = occupied.map { $0 % 80 }.max() ?? 0
                    let minY = occupied.map { $0 / 80 }.min() ?? 0, maxY = occupied.map { $0 / 80 }.max() ?? 0
                    let bounds = occupied.isEmpty ? CGRect.null : CGRect(x: Double(minX)/80, y: Double(79-maxY)/80,
                        width: Double(maxX-minX+1)/80, height: Double(maxY-minY+1)/80)
                    loaded.append(Frame(image: image, placement: placement, hitMask: mask, occupiedBounds: bounds))
                }
                frames[clip.state] = loaded
            }
            speechFrames = try manifest.speechFrames.map { try Self.load(root.appendingPathComponent($0.resource)) }
        } catch {
            frames.removeAll(); failure = "Sprite loading failed: \(error)"
            missingStates = Set(DuckState.allCases.filter { $0 != .timeout })
            NSLog("%@ — using pink square placeholders", failure!)
        }
        frameCounts = counts
    }
    public func frame(state: DuckState, index: Int) -> Frame? {
        guard let clip = frames[state], clip.indices.contains(index) else { return nil }
        return clip[index]
    }
    public func occupiedBounds(state: DuckState) -> CGRect? {
        guard let clip = frames[state] else { return nil }
        let result = clip.reduce(CGRect.null) { $0.union($1.occupiedBounds) }
        return result.isNull ? nil : result
    }
    private static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0 else {
            throw AssetError.invalidFrame(url.lastPathComponent)
        }
        return image
    }
    private enum AssetError: Error { case invalidManifest, invalidFrame(String) }
}
