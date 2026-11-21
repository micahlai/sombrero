import AppKit
import PetCore

public enum AppArtwork {
    /// An alpha-mask template lets macOS choose the correct menu-bar tint.
    public static let controlBarIcon: NSImage? = {
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for suffix in ["", "@2x", "@3x"] {
            let path = "Controls/DuckTemplate\(suffix).png"
            let candidates = bases.flatMap { base in
                ["\(PetConstants.Assets.resourceBundle)/\(path)",
                 "\(PetConstants.Assets.resourceBundle)/Contents/Resources/\(path)"]
                    .map { base.appendingPathComponent($0) }
            }
            if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
               let data = try? Data(contentsOf: url),
               let representation = NSBitmapImageRep(data: data) {
                representation.size = image.size
                image.addRepresentation(representation)
            }
        }
        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = "sombrero controls"
        return image
    }()
}
