import Foundation

public enum WindowPeekPlacement {
    public static func origin(window: PetRect, workArea: PetRect, viewportSize: Double, isFullScreen: Bool = false,
                              horizontalFraction: Double = 0.5, visibleBounds: PetRect? = nil, baselineY: Double? = nil,
                              minimumClearance: Double = PetConstants.WindowEntry.minimumClearanceAbove) -> PetPoint? {
        guard window.isValid, workArea.isValid, viewportSize.isFinite, viewportSize > 0,
              horizontalFraction.isFinite, (0...1).contains(horizontalFraction), !isFullScreen else { return nil }
        let bounds = visibleBounds ?? PetConstants.Geometry.fallbackWindowBounds.scaled(by: viewportSize)
        let ground = PetConstants.Geometry.groundAnchor
        // 4c's drawn ledge is separate from the shared ground used by normal clips.
        let baseline = baselineY ?? viewportSize*ground.y
        guard baseline.isFinite else { return nil }
        let point = PetPoint(x: window.x+window.width*horizontalFraction-viewportSize*ground.x,
                             y: window.maxY+PetConstants.WindowEntry.anchorOffsetAbove-baseline)
        let painted = bounds.offsetBy(x: point.x, y: point.y)
        let margin = PetConstants.WindowEntry.horizontalMargin
        guard window.maxY > workArea.y,
              workArea.maxY-window.maxY >= minimumClearance,
              painted.x >= max(workArea.x,window.x)+margin,
              painted.maxX <= min(workArea.maxX,window.maxX)-margin,
              workArea.contains(painted) else { return nil }
        return point
    }
    /// The target top strip and the duck's entire clearance rectangle must be
    /// unobstructed by windows in front of this candidate.
    public static func isUnobstructed(window: PetRect, origin: PetPoint, visibleBounds: PetRect, occluders: [PetRect]) -> Bool {
        let painted = visibleBounds.offsetBy(x: origin.x, y: origin.y)
        let topStrip = PetRect(x: painted.x, y: window.maxY-PetConstants.WindowEntry.visibleTopStripHeight,
                              width: painted.width, height: painted.maxY-window.maxY+PetConstants.WindowEntry.visibleTopStripHeight)
        return !occluders.contains { $0.intersects(topStrip) }
    }
}
