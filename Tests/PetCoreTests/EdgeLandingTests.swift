import XCTest
import PetCore

final class EdgeLandingTests: XCTestCase {
    func pixels(width: Int = 80, height: Int = 160, color: (Int,Int) -> UInt8) -> [UInt8] {
        (0..<height).flatMap { y in (0..<width).flatMap { x -> [UInt8] in
            let value = color(x,y); return [value,value,value,255]
        } }
    }

    func testLandingDetectorFindsAndDeduplicatesFullWidthEdges() {
        let image = pixels { _,y in y < 40 ? 240 : y < 110 ? 60 : 190 }
        XCTAssertEqual(HorizontalLandingEdges.rows(rgba:image,width:80,height:160,bytesPerRow:320),[40,110])
        let thin = pixels { _,y in y == 80 ? 0 : 240 }
        XCTAssertEqual(HorizontalLandingEdges.rows(rgba:thin,width:80,height:160,bytesPerRow:320).count,1)
    }

    func testLandingDetectorRejectsTextVerticalEdgesAndGradients() {
        let text = pixels { x,y in (x%20 < 8 && y%25 < 10) ? 20 : 240 }
        let vertical = pixels { x,_ in x < 40 ? 0 : 255 }
        let gradient = pixels { _,y in UInt8(y) }
        for image in [text,vertical,gradient] {
            XCTAssertTrue(HorizontalLandingEdges.rows(rgba:image,width:80,height:160,bytesPerRow:320).isEmpty)
        }
        XCTAssertTrue(HorizontalLandingEdges.rows(rgba:[],width:80,height:160,bytesPerRow:320).isEmpty)
    }

    func testScreenshotRowsMapToFeetWithRandomChoiceAndExactFallback() throws {
        let fallback = PetPoint(x:-1500,y:-90)
        let plan = try XCTUnwrap(EdgeLandingPlan(area:PetRect(x:-1440,y:-200,width:1440,height:900),fallback:fallback,
            bounds:PetRect(x:100,y:80,width:90,height:140),baselineOffset:80))
        let options = plan.candidates(rows:[100,300],imageHeight:Int(plan.region.height))
        XCTAssertEqual(options.count,2)
        XCTAssertEqual(options[0].y+80,plan.region.maxY-100,accuracy:0.001)
        XCTAssertEqual(options[1].y+80,plan.region.maxY-300,accuracy:0.001)
        XCTAssertEqual(options[0].x,fallback.x)
        XCTAssertEqual(plan.choose(rows:[100,300],imageHeight:Int(plan.region.height),sample:0),options[0])
        XCTAssertEqual(plan.choose(rows:[100,300],imageHeight:Int(plan.region.height),sample:0.99),options[1])
        XCTAssertEqual(plan.choose(rows:[],imageHeight:0,sample:0.5),fallback)
        // Retina/downsampled pixels must map through the actual captured region.
        XCTAssertEqual(plan.candidates(rows:[200],imageHeight:2*Int(plan.region.height))[0],options[0])
    }

    func testLandingCannotEnterOccludedIntervalsOrLeaveAllowedArea() throws {
        let plan = try XCTUnwrap(EdgeLandingPlan(area:PetRect(x:0,y:0,width:1000,height:800),
            fallback:PetPoint(x:0,y:100),bounds:PetRect(x:100,y:80,width:90,height:140),baselineOffset:80,
            intervals:[.init(lower:100,upper:200),.init(lower:400,upper:500)]))
        let rows = [100.0,250,450].map { Int(plan.region.maxY-($0+80)) }
        let options = plan.candidates(rows:rows,imageHeight:Int(plan.region.height))
        XCTAssertEqual(options.map(\.y),[100,450])
        XCTAssertTrue(plan.candidates(rows:[-1,10000],imageHeight:100).isEmpty)
        XCTAssertNil(EdgeLandingPlan(area:PetRect(x:0,y:0,width:1000,height:800),fallback:PetPoint(x:-500,y:0),
            bounds:PetRect(x:100,y:80,width:90,height:140),baselineOffset:80))
        let clipped = try XCTUnwrap(EdgeLandingPlan(area:PetRect(x:0,y:0,width:1000,height:800),
            fallback:PetPoint(x:-100.75,y:100),bounds:PetRect(x:100,y:80,width:90,height:140),baselineOffset:80))
        XCTAssertEqual(clipped.region.x,0)
        XCTAssertEqual(clipped.fallback.x,-100.75)
        XCTAssertEqual(clipped.region.width,89.25,accuracy:0.001)
    }
}
