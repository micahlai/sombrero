import AppKit
import CoreText
import PetCore

/// Project typography for speech-bubble text. Native menus use macOS defaults.
/// Font registration is process-scoped, so the bundled face needs no system installation.
public enum AppTypography {
    public static let bodySize: CGFloat = PetConstants.Speech.defaultFontSize

    public static let postScriptName: String? = {
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        let candidates = bases.flatMap { base in
            ["\(PetConstants.Assets.resourceBundle)/Fonts/MatchaStyle.otf", "\(PetConstants.Assets.resourceBundle)/Contents/Resources/Fonts/MatchaStyle.otf"].map { base.appendingPathComponent($0) }
        }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let provider = CGDataProvider(url: url as CFURL),
              let face = CGFont(provider), let name = face.postScriptName as String? else {
            NSLog("Matcha Style resource could not be loaded; using system typography")
            return nil
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let registrationError = error?.takeRetainedValue()
            guard let registrationError,
                  CFErrorGetCode(registrationError) == CTFontManagerError.alreadyRegistered.rawValue else {
                NSLog("Matcha Style could not be registered: %@", String(describing: registrationError))
                return nil
            }
        }
        return name
    }()

    public static func font(size: CGFloat = bodySize) -> NSFont {
        let pointSize = size.isFinite && size > 0 ? size : bodySize
        if let name = postScriptName, let font = NSFont(name: name, size: pointSize) { return font }
        return NSFont.systemFont(ofSize: pointSize)
    }
}
