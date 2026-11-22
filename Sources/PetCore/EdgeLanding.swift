import Foundation

/// Narrow screenshot region in AppKit coordinates; row zero in the image is its top.
public struct EdgeLandingPlan {
    public let region: PetRect
    public let fallback: PetPoint
    public let baselineOffset: Double
    public let intervals: [WindowSidePlacement.Interval]

    public init?(area: PetRect, fallback: PetPoint, bounds: PetRect, baselineOffset: Double,
                 intervals: [WindowSidePlacement.Interval]? = nil) {
        guard area.isValid, bounds.isValid, baselineOffset.isFinite, fallback.x.isFinite, fallback.y.isFinite else { return nil }
        let ranges = intervals ?? [.init(lower: area.y-bounds.y, upper: area.maxY-bounds.maxY)]
        guard ranges.allSatisfy({ $0.lower.isFinite && $0.upper.isFinite && $0.upper >= $0.lower }),
              let low = ranges.map(\.lower).min(), let high = ranges.map(\.upper).max(), high >= low else { return nil }
        // The authored 4b cut can leave a few painted pixels outside the screen.
        // Capture the visible footprint while keeping that calibrated x intact.
        let left = max(area.x,fallback.x+bounds.x), right = min(area.maxX,fallback.x+bounds.maxX)
        guard right-left >= max(12,bounds.width*0.7) else { return nil }
        let bottom = max(area.y, low+baselineOffset-4)
        let top = min(area.maxY, high+baselineOffset+4)
        guard top-bottom >= 8 else { return nil }
        self.region = PetRect(x: left, y: bottom, width: right-left, height: top-bottom)
        self.fallback = fallback; self.baselineOffset = baselineOffset; self.intervals = ranges
    }

    public func candidates(rows: [Int], imageHeight: Int) -> [PetPoint] {
        guard imageHeight > 0 else { return [] }
        return rows.filter { $0 >= 0 && $0 < imageHeight }.compactMap { row in
            let y = region.maxY-Double(row)*region.height/Double(imageHeight)-baselineOffset
            guard intervals.contains(where: { y >= $0.lower && y <= $0.upper }) else { return nil }
            return PetPoint(x: fallback.x, y: y)
        }
    }

    public func choose(rows: [Int], imageHeight: Int, sample: Double) -> PetPoint {
        let options = candidates(rows: rows, imageHeight: imageHeight)
        guard !options.isEmpty, sample.isFinite, (0..<1).contains(sample) else { return fallback }
        return options[min(options.count-1, Int(sample*Double(options.count)))]
    }
}

/// Looks for a coherent horizontal color step across most of a strip, rather
/// than text, short strokes, vertical borders, or gradual wallpaper gradients.
public enum HorizontalLandingEdges {
    public static func rows(rgba: [UInt8], width: Int, height: Int, bytesPerRow: Int,
                            minimumContrast: Double = 18, minimumCoverage: Double = 0.75) -> [Int] {
        guard width >= 12, height >= 8, bytesPerRow >= width*4,
              rgba.count >= bytesPerRow*height else { return [] }
        var peaks: [(row: Int, score: Double)] = []
        var lastQualifiedRow = -100
        let margin = max(1, width/20), count = width-2*margin
        for y in 2..<(height-2) {
            var differences: [(Double, Double, Double)] = []
            var red = 0.0, green = 0.0, blue = 0.0
            for x in margin..<(width-margin) {
                func channel(_ c: Int) -> Double {
                    let above = Int(rgba[(y-2)*bytesPerRow+x*4+c])+Int(rgba[(y-1)*bytesPerRow+x*4+c])
                    let below = Int(rgba[y*bytesPerRow+x*4+c])+Int(rgba[(y+1)*bytesPerRow+x*4+c])
                    return Double(below-above)/2
                }
                let r = channel(0), g = channel(1), b = channel(2)
                differences.append((r,g,b)); red += r; green += g; blue += b
            }
            red /= Double(count); green /= Double(count); blue /= Double(count)
            let score = (abs(red)+abs(green)+abs(blue))/3
            guard score >= minimumContrast else { continue }
            let magnitude = sqrt(red*red+green*green+blue*blue)
            var run = 0, longest = 0
            for (r,g,b) in differences {
                let contrast = (abs(r)+abs(g)+abs(b))/3
                let length = sqrt(r*r+g*g+b*b)
                if contrast >= minimumContrast && r*red+g*green+b*blue >= 0.8*length*magnitude {
                    run += 1; longest = max(longest,run)
                } else { run = 0 }
            }
            guard Double(longest)/Double(count) >= minimumCoverage else { continue }
            // Collapse the thickness/antialiasing of one edge into one candidate.
            if let last = peaks.last, y-lastQualifiedRow <= 6 {
                if score > last.score { peaks[peaks.count-1] = (y,score) }
            } else { peaks.append((y,score)) }
            lastQualifiedRow = y
        }
        return peaks.map(\.row)
    }
}
