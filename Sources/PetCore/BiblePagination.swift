import Foundation

public enum BiblePagination {
    /// Keep every source character, splitting at whitespace when possible.
    /// The host supplies font/layout measurement; a single oversized glyph still progresses.
    public static func pages(_ text: String, fits: (String)->Bool) -> [String] {
        let characters=Array(text)
        guard !characters.isEmpty else { return [""] }
        var start=0, pages: [String]=[]
        while start<characters.count {
            var lower=1, upper=characters.count-start, count=1
            while lower<=upper {
                let middle=(lower+upper)/2
                if fits(String(characters[start..<start+middle])) { count=middle; lower=middle+1 }
                else { upper=middle-1 }
            }
            var end=min(characters.count,start+count)
            if end<characters.count, let space=characters[start..<end].lastIndex(where:{ $0.isWhitespace }), space>start { end=space+1 }
            pages.append(String(characters[start..<end])); start=end
        }
        return pages
    }
}
