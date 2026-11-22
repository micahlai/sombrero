import XCTest
import PetCore

final class MessagingTests: XCTestCase {
    func testSenderNamesRoundTripAndLegacyMessagesStillDecode() throws {
        let message=ChatMessage(id:UUID().uuidString,pairID:UUID().uuidString,senderID:UUID().uuidString,
            recipientID:UUID().uuidString,clientRequestID:UUID().uuidString,body:RichMessageBody(text:"Hi"),
            attachment:nil,createdAt:Date(),senderName:"Micah")
        let data=try MessagingJSON.encoder().encode(message)
        let decoded=try MessagingJSON.decoder().decode(ChatMessage.self,from:data)
        XCTAssertEqual(decoded.displaySenderName,"Micah")
        var legacy=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        legacy.removeValue(forKey:"senderName")
        let old=try MessagingJSON.decoder().decode(ChatMessage.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(old.senderName); XCTAssertTrue(old.isValid)
        var replica=MessageReplica(); replica.upsert(message); replica.upsert(old)
        XCTAssertEqual(replica.messages[0].displaySenderName,"Micah")
    }
    let identity=ChatIdentity(deviceID:"11111111-1111-4111-8111-111111111111",peerID:"22222222-2222-4222-8222-222222222222",pairID:"33333333-3333-4333-8333-333333333333")
    func message(readAt: Date? = nil) -> ChatMessage {
        ChatMessage(id:"44444444-4444-4444-8444-444444444444",pairID:identity.pairID,senderID:identity.peerID,
                    recipientID:identity.deviceID,clientRequestID:"55555555-5555-4555-8555-555555555555",
                    body:RichMessageBody(text:"Hello 🦆"),attachment:nil,createdAt:Date(timeIntervalSince1970:100),readAt:readAt)
    }
    func testWireRoundTripAndOptionalFormattingDefaults() throws {
        let body=try MessagingJSON.decoder().decode(RichMessageBody.self,from:Data("{\"version\":1,\"runs\":[{\"text\":\"Hi\",\"bold\":true}]}".utf8))
        XCTAssertEqual(body.runs,[RichTextRun(text:"Hi",bold:true)])
        let value=message(readAt:Date(timeIntervalSince1970:100.125))
        XCTAssertEqual(try MessagingJSON.decoder().decode(ChatMessage.self,from:MessagingJSON.encoder().encode(value)),value)
    }
    func testMessageBoundsAndFixedPeerIdentity() {
        XCTAssertTrue(identity.isValid); XCTAssertTrue(message().isValid); XCTAssertTrue(message().belongs(to:identity))
        XCTAssertFalse(message().belongs(to:ChatIdentity(deviceID:identity.deviceID,peerID:UUID().uuidString,pairID:identity.pairID)))
        XCTAssertFalse(ChatIdentity(deviceID:"../outside",peerID:identity.peerID,pairID:identity.pairID).isValid)
        XCTAssertFalse(RichMessageBody(text:String(repeating:"a",count:20_001)).isValid)
        XCTAssertFalse(RichMessageBody(runs:[],version:99).isValid)
        XCTAssertTrue(RichMessageBody(text:String(repeating:"🦆",count:20_000)).isValid)
    }
    func testSyncCommitsMessagesAndCursorTogetherAndReadIsMonotonic() throws {
        let original=MessageReplica()
        var first=try original.applying(MessageSyncPage(cursor:1,hasMore:false,changes:[MessageChange(sequence:1,type:"message",message:message())]),identity:identity)
        XCTAssertEqual(original.cursor,0); XCTAssertTrue(original.messages.isEmpty)
        XCTAssertEqual(first.cursor,1); XCTAssertEqual(first.messages.count,1)
        first.upsert(message(readAt:Date(timeIntervalSince1970:200)))
        let next=try first.applying(MessageSyncPage(cursor:2,hasMore:false,changes:[MessageChange(sequence:2,type:"message",message:message())]),identity:identity)
        XCTAssertNotNil(next.messages[0].readAt)
        XCTAssertEqual(next.messages.count,1)
    }
    func testInvalidSyncCannotAdvanceCursorOrLeakAnotherPair() throws {
        var state=MessageReplica()
        state=try state.applying(MessageSyncPage(cursor:1,hasMore:false,changes:[MessageChange(sequence:1,type:"message",message:message())]),identity:identity)
        for page in [MessageSyncPage(cursor:0,hasMore:false,changes:[]),
                     MessageSyncPage(cursor:2,hasMore:true,changes:[]),
                     MessageSyncPage(cursor:2,hasMore:false,changes:[MessageChange(sequence:1,type:"read",message:message())])] {
            var rejected=false
            do { _ = try state.applying(page,identity:identity) } catch { rejected=true }
            XCTAssertTrue(rejected); XCTAssertEqual(state.cursor,1)
        }
        var rejected=false
        do {
            _ = try MessageReplica().applying(MessageSyncPage(cursor:1,hasMore:false,changes:[MessageChange(sequence:1,type:"message",message:message())]),
                identity:ChatIdentity(deviceID:identity.deviceID,peerID:identity.peerID,pairID:UUID().uuidString))
        } catch { rejected=true }
        XCTAssertTrue(rejected)
    }
    func testReopenPhotoAndCameraDuringExitRetainsOneRequest() {
        let routes: [(DuckRequest,DuckState,DuckState,DuckState)]=[(.photoShow,.grabPhoto,.showingPhoto,.putPhotoAway),(.photoTake,.grabCamera,.cameraIdle,.deliverPhoto)]
        for (request,entry,held,exit) in routes {
            var duck=DuckController(); duck.request(request)
            XCTAssertEqual(duck.state,entry)
            while duck.state != held { duck.complete { 0 } }
            if request == .photoTake { duck.takingPhoto=false }
            else { duck.cancel(request) }
            duck.complete { 0 }
            XCTAssertEqual(duck.state,exit)
            duck.request(request); duck.request(request)
            XCTAssertEqual(duck.pending,[request])
            duck.complete { 0 }; XCTAssertEqual(duck.state,entry)
        }
    }
    func testCancelCameraDoesNotPretendToExposeOrDeliverAPhoto() {
        var duck=DuckController(); duck.request(.photoTake)
        duck.complete { 0 }; XCTAssertEqual(duck.state,.cameraIdle)
        duck.cancel(.photoTake); duck.complete { 0 }
        XCTAssertEqual(duck.state,.grabCamera); XCTAssertTrue(duck.isReversingCamera)
        duck.complete { 0 }
        XCTAssertEqual(duck.state,.look); XCTAssertNil(duck.active)
        duck.request(.photoTake); duck.complete { 0 }
        duck.takingPhoto=false; duck.complete { 0 }
        XCTAssertEqual(duck.state,.deliverPhoto)
    }
    func testReopenCameraDuringReverseQueuesNewGrabWithoutInterruptingStow() {
        var duck=DuckController(); duck.request(.photoTake); duck.complete { 0 }
        duck.cancel(.photoTake); duck.complete { 0 }
        XCTAssertTrue(duck.isReversingCamera)
        let token=duck.generation
        duck.request(.photoTake); duck.request(.photoTake)
        XCTAssertEqual(duck.pending,[.photoTake]); XCTAssertEqual(duck.generation,token)
        duck.complete { 0 }
        XCTAssertEqual(duck.state,.grabCamera); XCTAssertFalse(duck.isReversingCamera)
        XCTAssertTrue(duck.takingPhoto); XCTAssertTrue(duck.pending.isEmpty)
        duck.complete { 0 }; XCTAssertEqual(duck.state,.cameraIdle)
    }
}
