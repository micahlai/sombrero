import XCTest
import PetCore

final class EntryPlacementTests: XCTestCase {
    let area=PetRect(x:-1000,y:0,width:1000,height:800)
    let artwork=PeekArtwork(viewportSize:300,cutX:100)
    let bounds=PetRect(x:100,y:80,width:90,height:140)
    func testPaintedBoundsCanReachEveryCornerDespiteTransparentCanvas() {
        for (x,y) in [(-9999.0,-9999.0),(9999,-9999),(-9999,9999),(9999,9999)] {
            let origin=Placement.clamp(PetPoint(x:x,y:y),visibleBounds:bounds,to:area)
            let painted=bounds.offsetBy(x:origin.x,y:origin.y)
            XCTAssertEqual(painted.x,x<0 ? area.x : area.maxX-bounds.width)
            XCTAssertEqual(painted.y,y<0 ? area.y : area.maxY-bounds.height)
            XCTAssertTrue(area.contains(painted))
        }
    }
    func testVisiblePlacementRoundTripAndLegacyPreferenceMigration() throws {
        let display=PetDisplay(id:"left",workArea:area)
        let origin=PetPoint(x:area.x-bounds.x,y:area.maxY-bounds.maxY)
        let saved=Placement.save(origin:origin,visibleBounds:bounds,display:display)
        XCTAssertEqual(saved.usesVisibleBounds,true)
        XCTAssertEqual(try XCTUnwrap(Placement.restore(saved,viewportSize:300,visibleBounds:bounds,displays:[display],fallbackID:nil)),origin)
        let old=SavedPlacement(displayID:"left",normalizedX:0.4,normalizedY:0.2)
        let expected=try XCTUnwrap(Placement.restore(old,size:300,displays:[display],fallbackID:nil))
        XCTAssertEqual(try XCTUnwrap(Placement.restore(old,viewportSize:300,visibleBounds:bounds,displays:[display],fallbackID:nil)),expected)
    }
    func testScreenEntryIsUniformVerticallyAndMirrorsOnlyTheRight() {
        let low=ScreenEntryPlacement.choose(screen:area,referenceBounds:bounds,artwork:artwork,sideSample:0,heightSample:0)
        let high=ScreenEntryPlacement.choose(screen:area,referenceBounds:bounds,artwork:artwork,sideSample:0.9,heightSample:1)
        let quarter=ScreenEntryPlacement.choose(screen:area,referenceBounds:bounds,artwork:artwork,sideSample:0,heightSample:0.25)
        XCTAssertEqual(low.edge,.left); XCTAssertFalse(low.flipsAnimation)
        XCTAssertEqual(high.edge,.right); XCTAssertTrue(high.flipsAnimation)
        XCTAssertEqual(low.origin.x+artwork.cutX,area.x+PetConstants.ScreenEntry.edgeOffset)
        XCTAssertEqual(high.origin.x+artwork.viewportSize-artwork.cutX,area.maxX-PetConstants.ScreenEntry.edgeOffset)
        XCTAssertEqual(low.origin.y+bounds.y,area.y)
        XCTAssertEqual(high.origin.y+bounds.maxY,area.maxY)
        XCTAssertEqual(quarter.origin.y,low.origin.y+(high.origin.y-low.origin.y)*0.25,accuracy:0.001)
    }
    func testWindowSideClearanceAndOcclusion() throws {
        let window=PetRect(x:-700,y:100,width:400,height:500)
        for edge in [ScreenEdge.left,.right] {
            XCTAssertEqual(edge.flipsWindowPeekAnimation, edge == .left)
            let point=try XCTUnwrap(WindowSidePlacement.origin(window:window,area:area,bounds:bounds,artwork:artwork,edge:edge,sample:0.5))
            let boundary = point.x+artwork.boundaryX(flipped:edge.flipsWindowPeekAnimation)
            XCTAssertEqual(boundary,edge == .left ? window.x-PetConstants.ScreenEntry.edgeOffset : window.maxX+PetConstants.ScreenEntry.edgeOffset,accuracy:0.001)
            XCTAssertTrue(area.contains(bounds.offsetBy(x:point.x,y:point.y)))
            XCTAssertFalse(window.intersects(bounds.offsetBy(x:point.x,y:point.y)))
        }
        XCTAssertNil(WindowSidePlacement.origin(window:area,area:area,bounds:bounds,artwork:artwork,edge:.left,sample:0.5))
        XCTAssertNil(WindowSidePlacement.origin(window:window,area:area,bounds:bounds,artwork:artwork,edge:.right,sample:0.5,occluders:[area]))
    }
    func testTopAnchorTracksWindowMovementAndResize() throws {
        let window=PetRect(x:-800,y:100,width:500,height:400)
        let point=try XCTUnwrap(WindowPeekPlacement.origin(window:window,workArea:area,viewportSize:300,horizontalFraction:0.5))
        let moved=window.offsetBy(x:40,y:20)
        let next=try XCTUnwrap(WindowPeekPlacement.origin(window:moved,workArea:area,viewportSize:300,horizontalFraction:0.5))
        XCTAssertEqual(next.x-point.x,40,accuracy:0.001); XCTAssertEqual(next.y-point.y,20,accuracy:0.001)
        let resized=PetRect(x:window.x,y:window.y,width:window.width+100,height:window.height+30)
        let last=try XCTUnwrap(WindowPeekPlacement.origin(window:resized,workArea:area,viewportSize:300,horizontalFraction:0.5))
        XCTAssertEqual(last.x-point.x,50,accuracy:0.001); XCTAssertEqual(last.y-point.y,30,accuracy:0.001)
        XCTAssertFalse(WindowPeekPlacement.isUnobstructed(window:window,origin:point,visibleBounds:bounds,occluders:[area]))
    }
    func testTopEntryUsesArtworkLedgeAndNormalClipsUseTheirGround() throws {
        let window=PetRect(x:-800,y:100,width:500,height:400)
        for viewport in [228.8,291.2,395.2] {
            let ledge=viewport*0.276
            let entry=try XCTUnwrap(WindowPeekPlacement.origin(window:window,workArea:area,viewportSize:viewport,baselineY:ledge))
            XCTAssertEqual(entry.y+ledge,window.maxY,accuracy:0.001)
            let normal=try XCTUnwrap(WindowPeekPlacement.origin(window:window,workArea:area,viewportSize:viewport))
            XCTAssertEqual(normal.y+viewport*PetConstants.Geometry.groundAnchor.y,window.maxY,accuracy:0.001)
        }
        XCTAssertNil(WindowPeekPlacement.origin(window:window,workArea:area,viewportSize:300,baselineY:.nan))
    }
    func testPersistentAndTemporaryAttachmentsDetachOnlyAtTheirBoundaries() {
        var model=PetAttachment();let target=WindowAttachment(windowID:42,horizontalFraction:0.5)
        model.enterWindow(target)
        for state in DuckState.allCases { model.didEnterState(state); XCTAssertEqual(model.window,target) }
        model.drag(); XCTAssertNil(model.window)
        for state in DuckState.allCases { model.didEnterState(state); XCTAssertNil(model.window) }
        let side=WindowSideAttachment(windowID:43,ownerPID:1,edge:.left,verticalFraction:0.5)
        model.enterSide(side); model.didEnterState(.peek); XCTAssertEqual(model.side,side)
        model.didEnterState(.alternateLook); XCTAssertNil(model.side); XCTAssertNil(model.window)
        model.enterWindow(target); XCTAssertEqual(model.window,target)
    }
    func testAllFourRecallWeightRowsAndVariants() {
        for (top,side,expected) in [(false,false,[1.0,0,0]),(true,false,[0.2,0.8,0]),(false,true,[0.5,0,0.5]),(true,true,[0.4,0.4,0.2])] {
            let weights=PetConstants.Animation.recallWeights(top:top,side:side)
            for (entry,value) in [(RecallEntry.screenEdge,expected[0]),(.windowTop,expected[1]),(.windowSide,expected[2])] where value>0 {
                let index=weights.firstIndex { $0.0 == entry }!
                let lower=weights.prefix(index).reduce(0) { $0+$1.1 }
                var controller=DuckController();controller.reset(to:.timeout)
                controller.recall(windowAvailable:top,sideAvailable:side) { lower+value/2 }
                XCTAssertEqual(controller.recallEntry,entry)
                XCTAssertEqual(controller.state,entry == .windowTop ? .windowPeek : .peek)
            }
        }
    }
}
