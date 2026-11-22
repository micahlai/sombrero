import Foundation

/// Runtime tuning lives here. Geometry uses macOS points, normalized rectangles
/// use the common square sprite viewport, and animation transforms stay in the
/// authored assets/duck/final-v1/animation-scales.json calibration file.
public enum PetConstants {
    public enum Animation {
        public static let drawingFPS = 6
        public static let updateFPS = 30.0
        public static let timerTolerance = 0.008
        public static let placeholderFrames = 10
        public static let speechFrameCount = 5
        public static let maximumFrameCount = 500
        public static let maximumCatchUpClips = 120
        public static let timeEpsilon = 1e-9
        public static let maximumQueuedRequests = 8
        public static func recallWeights(top: Bool, side: Bool) -> [(RecallEntry, Double)] {
            switch (top,side) {
            case (false,false): return [(.screenEdge,1)]
            case (true,false): return [(.screenEdge,0.2),(.windowTop,0.8)]
            case (false,true): return [(.screenEdge,0.5),(.windowSide,0.5)]
            case (true,true): return [(.screenEdge,0.4),(.windowTop,0.4),(.windowSide,0.2)]
            }
        }
        public static let legacyPetDuration = 2.0
        public static let defaultTransitions: [DuckState: [(DuckState, Double)]] = [
            .look: [(.look, 0.975), (.alternateLook, 0.02), (.wave, 0.02), (.sitDown, 0.005)],
            .alternateLook: [(.look, 0.8), (.wave, 0.2)], .wave: [(.look, 1)],
            .sitDown: [(.sitting, 1)], .standUp: [(.look, 1)],
            .sitting: [(.sitting, 0.985), (.sittingLook, 0.01), (.standUp, 0.005)],
            .sittingLook: [(.sittingLook, 0.1), (.sitting, 0.9)],
            .goodbye: [(.timeout, 1)], .peek: [(.alternateLook, 1)], .windowPeek: [(.sitting, 1)],
            .grabPhoto: [(.showingPhoto, 1)], .putPhotoAway: [(.look, 1)],
            .grabCamera: [(.cameraIdle, 1)], .deliverPhoto: [(.look, 1)],
            .grabBible: [(.bibleIdle, 1)], .stowBible: [(.look, 1)]
        ]
    }
    public enum Geometry {
        public static let viewportScale = 2.6
        public static let groundAnchor = PetPoint(x: 0.5, y: 0.26)
        public static let fallbackWindowBounds = PetRect(x: 0.33, y: 0.26, width: 0.34, height: 0.46)
        public static let placeholderBounds = PetRect(x: 0.4, y: 0.26, width: 0.2, height: 0.2)
        public static let freePlacementUsesWorkArea = false // false: physical screen edges/corners
        public static let initialNormalizedPosition = PetPoint(x: 0.85, y: 0.12)
    }
    public enum ScreenEntry {
        /// Inset of the artwork's vertical cut from the screen/window edge, in points.
        public static let edgeOffset = 0.0
        /// Authored vertical crop boundary in the 700px-wide 4b source drawings.
        public static let sourceCutX = 205.0
        public static let verticalMargin = 0.0
        public static let leftChance = 0.5
    }
    public enum WindowEntry {
        public static let minimumClearanceAbove = 160.0
        public static let anchorOffsetAbove = 0.0
        /// Horizontal ledge stroke in the 500px-tall 4c source drawings (top-left coordinates).
        public static let sourceLedgeY = 354.0
        public static let horizontalMargin = 8.0
        public static let minimumWindowWidth = 80.0
        public static let minimumWindowHeight = 60.0
        public static let minimumWindowAlpha = 0.1
        public static let geometryPollInterval = 0.1
        public static let candidateAnchorFractions = [0.5, 0.35, 0.65, 0.2, 0.8]
        public static let visibleTopStripHeight = 4.0
    }
    public enum Interaction {
        public static let dragThreshold = 5.0
        public static let recallTimerMinimumDelay = 0.01
        public static let awayMinuteOptions = [15, 60, 240]
        public static let secondsPerMinute = 60.0
    }
    public enum Size {
        public static let defaultPet = 112.0
        public static let minimumPet = 64.0
        public static let maximumPet = 200.0
        public static let options = [("Small", 88), ("Medium", 112), ("Large", 152)]
    }
    public enum Assets {
        public static let resourceBundle = "sombrero_PetAssets.bundle"
        public static let maskSize = 80
        public static let alphaThreshold: UInt8 = 20
        public static let hitPaddingPixels = 2
        public static let rgbaChannels = 4
        public static let bitsPerChannel = 8
    }
    public enum Speech {
        public static let width = 355.0 / 3
        public static let height = 400.0 / 3
        public static let gap = 8.0
        public static let sourceWidth = 700.0
        public static let sourceHeight = 500.0
        public static let crop = PetRect(x: 200, y: 40, width: 355, height: 400)
        public static let controls = PetRect(x: 0.12, y: 0.34, width: 0.76, height: 0.56)
        public static let fallback = PetRect(x: 0.04, y: 0.30, width: 0.92, height: 0.68)
        public static let controlSpacing = 1.5
        public static let buttonHeight = 14.0
        public static let bodyFontSize = 9.0
        public static let headingFontSize = 10.0
        public static let defaultFontSize = 18.0
        public static let ink = (red: 0.29, green: 0.23, blue: 0.17)
        public static let paper = (red: 1.0, green: 0.97, blue: 0.85)
        public static let fallbackCorner = PetPoint(x: 0.09, y: 0.08)
        public static let tailFraction = 0.14
        public static let sideAlignment = 0.3
        public static let verticalTextPadding = 3.0
        public static let horizontalTextPadding = 3.0
        public static let readerWidth = 220.0
        public static let readerMinimumHeight = 260.0
        public static let readerMaximumHeight = 260.0
        public static let readerFontSize = 12.0
        public static let readerMinimumTextHeight = 90.0
        public static let readerMaximumTextHeight = 90.0
    }
    public enum Bible {
        public static let excludedDays = 3
        public static let timerMinimumDelay = 1.0
    }
    public enum Appearance {
        public static let placeholderLabelSize = 12.0
        public static let badgeSize = 32.0
    }
}
