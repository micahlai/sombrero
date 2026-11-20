import Foundation

/// Geometry in macOS screen points. Clearance is sized to the duck viewport,
/// including faint art above its head, plus an eight-point gap above the window.
public enum WindowPeekPlacement {
    public static func origin(window: PetRect, workArea: PetRect, viewportSize: Double, isFullScreen: Bool = false) -> PetPoint? {
        let values = [window.x, window.y, window.width, window.height, workArea.x, workArea.y, workArea.width, workArea.height, viewportSize]
        guard values.allSatisfy(\.isFinite), !isFullScreen, viewportSize > 0,
              window.width > 0, window.height > 0, workArea.width > 0, workArea.height > 0 else { return nil }
        let top = window.y + window.height
        let baseline = top + 8
        let visibleHeight = viewportSize * 0.46
        let visibleWidth = viewportSize * 0.34
        guard top > workArea.y, baseline + visibleHeight <= workArea.y + workArea.height,
              window.width >= visibleWidth + 16 else { return nil }
        let left = max(window.x, workArea.x)
        let right = min(window.x + window.width, workArea.x + workArea.width)
        guard right - left >= visibleWidth + 16 else { return nil }
        let center = min(right - visibleWidth / 2 - 8, max(left + visibleWidth / 2 + 8, window.center.x))
        // Shared viewport baseline (also used by the missing-art pink square).
        return PetPoint(x: center - viewportSize / 2, y: baseline - viewportSize * 0.26)
    }
}
