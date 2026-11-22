import AppKit
import ScreenCaptureKit
import PetCore

/// Single, cropped, in-memory screenshots. No capture is attempted by previews
/// or tests until the real app starts, and this never uploads or saves pixels.
@MainActor
final class EdgeLandingCapture {
    typealias Capture = (CGRect, @escaping (CGImage?) -> Void) -> Void
    var isEnabled = false
    private var requestedPermission = false
    private let captureOverride: Capture?

    init(capture: Capture? = nil) { captureOverride = capture }

    var canRequestPermission: Bool {
        if #available(macOS 14, *) { return !CGPreflightScreenCaptureAccess() }
        return false
    }

    func requestPermission() {
        requestedPermission = true
        _ = CGRequestScreenCaptureAccess()
    }

    /// False means callers can use their fallback immediately, with no waiting.
    @discardableResult
    func capture(_ plan: EdgeLandingPlan, completion: @escaping ([Int], Int) -> Void) -> Bool {
        let rect = CGRect(x:plan.region.x,y:plan.region.y,width:plan.region.width,height:plan.region.height)
        let analyze: (CGImage?) -> Void = { image in
            guard let image, let rows = Self.edgeRows(in:image) else { completion([],0); return }
            completion(rows,image.height)
        }
        if let captureOverride { captureOverride(rect,analyze); return true }
        guard isEnabled else { return false }
        guard #available(macOS 14, *) else { return false }
        if !CGPreflightScreenCaptureAccess() {
            if !requestedPermission {
                requestedPermission = true
                // Keep the first entrance independent of the permission dialog.
                DispatchQueue.main.async { [weak self] in self?.requestPermission() }
            }
            return false
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rect) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        let local = CGRect(x:rect.minX-screen.frame.minX,y:screen.frame.maxY-rect.maxY,width:rect.width,height:rect.height)
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard let display = content.displays.first(where: { $0.displayID == id.uint32Value }) else { analyze(nil); return }
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = local
                configuration.width = max(1,Int(ceil(rect.width)))
                configuration.height = max(1,Int(ceil(rect.height)))
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
                analyze(image)
            } catch { analyze(nil) }
        }
        return true
    }

    static func edgeRows(in image: CGImage) -> [Int]? {
        let width = image.width, height = image.height, stride = width*4
        var pixels = [UInt8](repeating:0,count:stride*height)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,
                bytesPerRow:stride,space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            return true
        }
        guard rendered else { return nil }
        return HorizontalLandingEdges.rows(rgba:pixels,width:width,height:height,bytesPerRow:stride)
    }
}
