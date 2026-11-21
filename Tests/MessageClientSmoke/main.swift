import Foundation
import AppKit
import PetCore

private final class TestCredentials: MessageCredentialStorage {
    var values: [String:String]=[:]
    func read(account: String) throws -> String? { values[account] }
    func write(_ token: String,account: String) throws { values[account]=token }
    func remove(account: String) throws { values.removeValue(forKey:account) }
}
private final class TestProtocol: URLProtocol {
    static var server: TestServer!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code,data)=try Self.server.respond(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
private final class TestServer {
    let identity=ChatIdentity(deviceID:"11111111-1111-4111-8111-111111111111",peerID:"22222222-2222-4222-8222-222222222222",pairID:"33333333-3333-4333-8333-333333333333")
    let image=Data([137,80,78,71,13,10,26,10,0,0,0,0])
    lazy var attachment=ChatAttachment(id:UUID().uuidString.lowercased(),mediaType:"image/png",byteCount:image.count,sha256:MessageStore.digest(image),createdAt:Date())
    var offline=false, loseNextSend=false, corruptDownload=false
    var messages: [ChatMessage]=[], changes: [MessageChange]=[]
    var uploadIDs: [String]=[], sendIDs: [String]=[], downloads=0, readRequests=0
    let lock=NSRecursiveLock()
    func respond(_ request: URLRequest) throws -> (Int,Data) {
        lock.lock(); defer { lock.unlock() }
        if offline { throw URLError(.notConnectedToInternet) }
        precondition(request.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-token","Every request must authenticate")
        let path=request.url!.path
        if path == "/v1/me" { return (200,try MessagingJSON.encoder().encode(identity)) }
        if path == "/v1/attachments", request.httpMethod == "POST" {
            precondition(request.value(forHTTPHeaderField:"Content-Type") == "image/png")
            let id=request.value(forHTTPHeaderField:"X-Client-Upload-ID")!
            precondition(UUID(uuidString:id) != nil); uploadIDs.append(id)
            return (200,try MessagingJSON.encoder().encode(attachment))
        }
        if path == "/v1/messages", request.httpMethod == "POST" {
            struct Send: Decodable { let clientRequestID: String; let body: RichMessageBody; let attachmentID: String? }
            let bytes: Data
            if let body=request.httpBody { bytes=body }
            else if let stream=request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var result=Data(),buffer=[UInt8](repeating:0,count:4_096)
                while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count); if n<=0 { break }; result.append(buffer,count:n) }
                bytes=result
            } else { preconditionFailure("Send requires a JSON body") }
            let sent=try MessagingJSON.decoder().decode(Send.self,from:bytes)
            sendIDs.append(sent.clientRequestID)
            let message: ChatMessage
            if let prior=messages.first(where:{ $0.clientRequestID == sent.clientRequestID }) { message=prior }
            else {
                message=ChatMessage(id:UUID().uuidString.lowercased(),pairID:identity.pairID,senderID:identity.deviceID,recipientID:identity.peerID,
                    clientRequestID:sent.clientRequestID,body:sent.body,attachment:sent.attachmentID == nil ? nil : attachment,createdAt:Date())
                messages.append(message); append(message,type:"message")
            }
            if loseNextSend { loseNextSend=false; throw URLError(.networkConnectionLost) }
            return (200,try MessagingJSON.encoder().encode(message))
        }
        if path == "/v1/sync" {
            let cursor=Int(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first { $0.name == "cursor" }!.value!)!
            let events=changes.filter { $0.sequence>cursor }
            return (200,try MessagingJSON.encoder().encode(MessageSyncPage(cursor:changes.count,hasMore:false,changes:events)))
        }
        if path.hasSuffix("/read"), request.httpMethod == "PUT" {
            readRequests+=1
            let id=request.url!.deletingLastPathComponent().lastPathComponent
            guard let index=messages.firstIndex(where:{ $0.id == id && $0.recipientID == identity.deviceID }) else { return (403,Data()) }
            messages[index].readAt=messages[index].readAt ?? Date()
            append(messages[index],type:"read")
            return (200,try MessagingJSON.encoder().encode(messages[index]))
        }
        if path == "/v1/attachments/\(attachment.id)" {
            downloads+=1
            return (200,corruptDownload ? Data("bad checksum".utf8) : image)
        }
        preconditionFailure("Unexpected API request: \(request.httpMethod ?? "") \(path)")
    }
    func append(_ message: ChatMessage,type: String) { changes.append(MessageChange(sequence:changes.count+1,type:type,message:message)) }
    func receive() -> ChatMessage {
        let value=ChatMessage(id:UUID().uuidString.lowercased(),pairID:identity.pairID,senderID:identity.peerID,recipientID:identity.deviceID,
            clientRequestID:UUID().uuidString.lowercased(),body:RichMessageBody(text:"Incoming photo"),attachment:attachment,createdAt:Date())
        messages.append(value); append(value,type:"message"); return value
    }
}

@main
private struct MessageClientSmoke {
    @MainActor static func main() async throws {
        let root=URL(fileURLWithPath:".build/message-client-smoke-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let server=TestServer(); TestProtocol.server=server
        let options=URLSessionConfiguration.ephemeral; options.protocolClasses=[TestProtocol.self]
        let session=URLSession(configuration:options)
        let store=MessageStore(root:root.appendingPathComponent("messages"))
        let credentials=TestCredentials()
        let client=MessageService(store:store,credentials:credentials,session:session)
        defer { client.stop(); session.invalidateAndCancel() }
        precondition(!MessageService.validServerURL(URL(string:"http://sombrero.micahlai.com")!))
        precondition(!MessageService.validServerURL(URL(string:"https://user:password@example.com")!))
        precondition(!MessageService.validServerURL(URL(string:"https://example.com/not-an-origin")!))
        precondition(MessageService.validServerURL(URL(string:"http://127.0.0.1:8765")!))
        try await client.configure(serverURL:URL(string:"https://SOMBRERO.test:443/")!,token:"fixture-token")
        client.stop()
        let configuration=client.configuration!
        precondition(configuration.serverURL.absoluteString == "https://sombrero.test","Equivalent origins must share one history/outbox partition")
        let configData=try Data(contentsOf:store.root.appendingPathComponent("configuration.json"))
        precondition(!String(decoding:configData,as:UTF8.self).contains("fixture-token"),"Tokens must not enter on-disk configuration")

        // A lost server response must retain the same request ID and staged file.
        server.offline=true
        let image=root.appendingPathComponent("photo.png"); try server.image.write(to:image)
        let requestID=try client.enqueue(body:RichMessageBody(runs:[RichTextRun(text:"Hello",bold:true)]),attachment:image)
        try FileManager.default.removeItem(at:image)
        await client.refresh(); try await Task.sleep(nanoseconds:20_000_000)
        precondition(client.outbox.count == 1)
        let saved=try store.load(configuration)
        precondition(saved.outbox.first?.id == requestID)
        let staged=try store.outboxURL(name:saved.outbox[0].localAttachmentName!,configuration:configuration)
        precondition(FileManager.default.fileExists(atPath:staged.path),"Outbox owns a copy of its media")
        server.offline=false; server.loseNextSend=true
        await client.refresh()
        precondition(client.outbox.count == 1 && server.messages.count == 1)
        let reloaded=MessageService(store:store,credentials:credentials,session:session)
        defer { reloaded.stop() }
        precondition(reloaded.outbox.first?.id == requestID)
        await reloaded.refresh()
        precondition(reloaded.outbox.isEmpty && server.messages.count == 1)
        precondition(server.sendIDs.count == 2 && Set(server.sendIDs) == [requestID])
        precondition(server.uploadIDs == [requestID],"Committed upload is reused after a lost message response")
        precondition(!FileManager.default.fileExists(atPath:staged.path))
        print("PASS client: authenticated HTTPS, Keychain-only token, durable media/outbox, restart and lost-response retry without duplicates")

        // Showing metadata or a failed download must not clear the unread badge.
        let incoming=server.receive()
        await reloaded.refresh()
        precondition(reloaded.unreadIncomingCount == 1)
        server.corruptDownload=true
        var rejected=false
        do { _ = try await reloaded.attachmentURL(for:incoming) } catch { rejected=true }
        precondition(rejected && reloaded.unreadIncomingCount == 1)
        server.corruptDownload=false
        let cached=try await reloaded.attachmentURL(for:incoming)
        precondition(cached != nil && reloaded.unreadIncomingCount == 1)
        let downloads=server.downloads
        _ = try await reloaded.attachmentURL(for:incoming)
        precondition(server.downloads == downloads,"Verified media should load offline from cache")
        server.offline=true
        try reloaded.markRead(incoming)
        await reloaded.refresh(); try await Task.sleep(nanoseconds:20_000_000)
        precondition(reloaded.unreadIncomingCount == 0)
        let pendingReads=try store.load(configuration).pendingReadIDs
        precondition(pendingReads == [incoming.id])
        server.offline=false; await reloaded.refresh()
        let completedReads=try store.load(configuration).pendingReadIDs
        precondition(completedReads.isEmpty)
        precondition(server.readRequests == 1)
        print("PASS client: failed/checksum media stays unread, verified cache is reusable, read receipts persist offline and retry")

        // Drafts survive loss of their original files and are isolated by profile.
        let drafts=MessageDraftStore(profile:"pair-one",directory:root.appendingPathComponent("drafts"))
        let source=root.appendingPathComponent("draft.png"); try server.image.write(to:source)
        try drafts.save(body:RichMessageBody(text:"Draft"),attachment:source)
        try FileManager.default.removeItem(at:source)
        try drafts.save(body:RichMessageBody(text:"Still editing"),attachment:source)
        let restored=try drafts.load()!
        precondition(restored.body.plainText == "Still editing" && FileManager.default.fileExists(atPath:restored.attachment!.path))
        let other=MessageDraftStore(profile:"pair-two",directory:root.appendingPathComponent("drafts"))
        let otherDraft=try other.load(); precondition(otherDraft == nil)
        drafts.clear(); let clearedDraft=try drafts.load(); precondition(clearedDraft == nil)
        precondition(!FileManager.default.fileExists(atPath:restored.attachment!.path))
        print("PASS drafts: private staged attachments survive original-file removal and profiles cannot share unsent drafts")

        let app=NSApplication.shared; app.setActivationPolicy(.prohibited)
        let composer=MessageComposerWindow()
        let coordinator=MessageCoordinator(service:reloaded,composer:composer,draftDirectory:root.appendingPathComponent("composer-drafts"))
        defer { coordinator.stop() }
        func buttons(_ view:NSView)->[NSButton] {
            view.subviews.flatMap { child in (child as? NSButton).map { [$0] } ?? buttons(child) }
        }
        let send=buttons(composer.window.contentView!).first { $0.title=="Send" }!
        func prepare(_ text:String) {
            composer.setStatus("Ready")
            composer.setDraft(text:MessageRichText.attributed(from:RichMessageBody(text:text)),attachmentURL:nil)
            composer.show()
        }
        prepare("Close after acknowledgment")
        server.offline=true; send.performClick(nil)
        try await Task.sleep(nanoseconds:40_000_000)
        precondition(composer.window.isVisible && !send.isEnabled && reloaded.outbox.count==1,"Queued/offline is not yet sent; prevent double submission")
        server.offline=false; await reloaded.refresh()
        precondition(!composer.window.isVisible && reloaded.outbox.isEmpty,"Close in the same service change as the server acknowledgment")

        prepare("Old send, manually closed")
        server.offline=true; send.performClick(nil)
        try await Task.sleep(nanoseconds:40_000_000)
        precondition(reloaded.outbox.count==1 && !send.isEnabled)
        composer.window.close()
        prepare("A new draft stays open")
        server.offline=false; await reloaded.refresh()
        precondition(composer.window.isVisible && composer.draftText.string=="A new draft stays open","A late old acknowledgment must not close another draft")
        composer.window.close()
        print("PASS composer: closes immediately on send acknowledgment, stays open offline, prevents duplicate sends, and late acknowledgments cannot close new drafts")
    }
}
