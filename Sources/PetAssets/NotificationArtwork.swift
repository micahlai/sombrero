import Foundation
import CoreGraphics
import ImageIO
import PetCore

public enum NotificationArtwork {
    /// Verbatim authored canvases keep the watercolor mark registered as it loops.
    public static let frames: [CGImage] = {
        let bases=[Bundle.main.resourceURL,Bundle.main.bundleURL,Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        let roots=bases.flatMap { base in
            ["\(PetConstants.Assets.resourceBundle)/Notifications", "\(PetConstants.Assets.resourceBundle)/Contents/Resources/Notifications"]
                .map { base.appendingPathComponent($0) }
        }
        guard let root=roots.first(where:{ FileManager.default.fileExists(atPath:$0.appendingPathComponent("ex0000.png").path) }) else { return [] }
        let images=(0..<5).compactMap { index -> CGImage? in
            let path=root.appendingPathComponent(String(format:"ex%04d.png",index))
            guard let source=CGImageSourceCreateWithURL(path as CFURL,nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source,0,nil)
        }
        return images.count == 5 ? images : []
    }()
}
