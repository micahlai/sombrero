import Foundation
import PetCore

// A redirect may change the origin or downgrade HTTPS. Require the configured
// endpoint to respond directly rather than forwarding bearer credentials.
private final class MessageSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum MessageServiceError: LocalizedError {
    case notConfigured, invalidConfiguration, invalidMessage, unsupportedMedia, mediaTooLarge, invalidResponse
    case invalidLocalHistory, credentials, missingAttachment, server(Int)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Connect messaging in Messaging Settings first."
        case .invalidConfiguration: return "Use a public HTTPS server URL and a valid device token. HTTP is allowed only for localhost testing."
        case .invalidMessage: return "Enter a message or attach a photo/video. Messages support up to 20,000 characters and 1,000 formatting runs."
        case .unsupportedMedia: return "Choose a JPEG, PNG, GIF, HEIC photo, or MP4/MOV video."
        case .mediaTooLarge: return "Photos may be up to 10 MiB; videos may be up to 100 MiB."
        case .invalidResponse: return "The message server returned an unexpected response. Your queued messages are retained."
        case .invalidLocalHistory: return "Local messaging history could not be loaded. The original files have been preserved."
        case .credentials: return "The device token could not be accessed in Keychain."
        case .missingAttachment: return "The queued attachment is missing. Remove this queued message and attach the file again."
        case .server(let code):
            switch code {
            case 401,403: return "Messaging is not authorized. Check the server URL and device token in Messaging Settings."
            case 409: return "The server rejected a conflicting request. Your queued message is retained."
            case 413: return "This attachment exceeds the server's upload limit."
            case 503: return "The server's media storage is unavailable. Messaging will retry."
            default: return "The messaging server could not complete the request (HTTP \(code))."
            }
        }
    }
}

@MainActor
final class MessageService {
    private let store: MessageStore
    private let credentials: MessageCredentialStorage
    private let session: URLSession
    private var replica=MessageReplica()
    private var pollingTask: Task<Void,Never>?
    private var generation=UUID()
    private var synchronizingGeneration: UUID?
    private var failureCount=0
    private var retryAt=Date.distantPast
    private var historyLoaded=true
    private(set) var configuration: MessageConfiguration?
    private(set) var connectionStatus="Not connected"
    private(set) var lastError: String?
    var onChange: (() -> Void)?
    var messages: [ChatMessage] { replica.messages }
    var outbox: [OutgoingMessage] { replica.outbox }
    var unreadIncomingCount: Int {
        guard let identity=configuration?.identity else { return 0 }
        return replica.messages.filter { $0.recipientID == identity.deviceID && $0.readAt == nil }.count
    }
    var nextUnreadMessage: ChatMessage? {
        guard let deviceID=configuration?.deviceID else { return nil }
        return replica.messages.first { $0.recipientID == deviceID && $0.readAt == nil }
    }

    init(store: MessageStore = MessageStore(), credentials: MessageCredentialStorage = MessageCredentials(), session: URLSession? = nil) {
        self.store=store; self.credentials=credentials
        if let session { self.session=session }
        else {
            let options=URLSessionConfiguration.ephemeral
            options.timeoutIntervalForRequest=30; options.timeoutIntervalForResource=300
            options.urlCache=nil; options.httpCookieStorage=nil
            self.session=URLSession(configuration:options,delegate:MessageSessionDelegate(),delegateQueue:nil)
        }
        do {
            configuration=try store.loadConfiguration()
            if let configuration {
                replica=try store.load(configuration)
                connectionStatus="Waiting to connect"
            }
        } catch {
            historyLoaded=false; lastError=error.localizedDescription; connectionStatus="Local history unavailable"
        }
    }

    nonisolated static func validServerURL(_ url: URL) -> Bool {
        guard let parts=URLComponents(url:url,resolvingAgainstBaseURL:false), let host=parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || ((parts.port ?? 0)>0 && (parts.port ?? 0)<=65_535) else { return false }
        if parts.scheme?.lowercased() == "https" { return true }
        return parts.scheme?.lowercased() == "http" && ["localhost","127.0.0.1","::1","[::1]"].contains(host.lowercased())
    }

    func configure(serverURL: URL, token: String) async throws {
        let token=token.trimmingCharacters(in:.whitespacesAndNewlines)
        guard Self.validServerURL(serverURL), !token.isEmpty, token.utf8.count<=4_096,
              token.unicodeScalars.allSatisfy({ $0.value>32 && $0.value<127 }) else { throw MessageServiceError.invalidConfiguration }
        var origin=URLComponents(url:serverURL,resolvingAgainstBaseURL:false)!
        origin.scheme=origin.scheme?.lowercased(); origin.host=origin.host?.lowercased(); origin.path=""
        if origin.scheme == "https" && origin.port == 443 { origin.port=nil }
        let serverURL=origin.url!
        stop()
        let operation=generation
        connectionStatus="Connecting…"; lastError=nil; notify()
        do {
            let identity: ChatIdentity=try await jsonRequest("GET",path:"v1/me",server:serverURL,token:token)
            guard generation == operation else { throw CancellationError() }
            guard identity.isValid else { throw MessageServiceError.invalidResponse }
            let account=UUID().uuidString.lowercased()
            let next=MessageConfiguration(serverURL:serverURL,identity:identity,credentialAccount:account)
            let loaded=try store.load(next)
            try credentials.write(token,account:account)
            do { try store.saveConfiguration(next) }
            catch { try? credentials.remove(account:account); throw error }
            let oldAccount=configuration?.credentialAccount
            configuration=next; replica=loaded; historyLoaded=true
            failureCount=0; retryAt = .distantPast; lastError=nil; connectionStatus="Connected"
            if let oldAccount { try? credentials.remove(account:oldAccount) }
            notify(); start()
        } catch {
            if generation == operation {
                connectionStatus="Connection failed"; lastError=error.localizedDescription; notify()
                // A failed replacement must not silently stop the previous,
                // still-valid connection and its durable outbox.
                if configuration != nil { start() }
            }
            throw error
        }
    }

    func removeConfiguration() throws {
        stop()
        try store.clearConfiguration()
        if let configuration { try credentials.remove(account:configuration.credentialAccount) }
        configuration=nil; replica=MessageReplica(); historyLoaded=true
        connectionStatus="Not connected"; lastError=nil; notify()
    }

    func start() {
        guard pollingTask == nil, configuration != nil, historyLoaded else { return }
        pollingTask=Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.synchronize(force:false)
                do { try await Task.sleep(nanoseconds:5_000_000_000) } catch { return }
            }
        }
    }
    func stop() {
        pollingTask?.cancel(); pollingTask=nil
        generation=UUID(); synchronizingGeneration=nil
    }
    func refresh() async { await synchronize(force:true) }

    @discardableResult
    func enqueue(body: RichMessageBody, attachment: URL? = nil) throws -> String {
        guard let configuration else { throw MessageServiceError.notConfigured }
        guard historyLoaded else { throw MessageServiceError.invalidLocalHistory }
        guard body.isValid, !body.plainText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || attachment != nil else { throw MessageServiceError.invalidMessage }
        let id=UUID().uuidString.lowercased()
        var attachmentName: String?, mediaType: String?, copiedURL: URL?
        if let attachment {
            let scoped=attachment.startAccessingSecurityScopedResource()
            defer { if scoped { attachment.stopAccessingSecurityScopedResource() } }
            let type=try Self.mediaType(of:attachment)
            let info=try attachment.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            guard info.isRegularFile == true else { throw MessageServiceError.unsupportedMedia }
            let maximum=type.hasPrefix("video/") ? MessageMediaTypes.maximumVideoBytes : MessageMediaTypes.maximumImageBytes
            guard let size=info.fileSize, size>0, size<=maximum else { throw MessageServiceError.mediaTooLarge }
            let suffix=Self.fileExtension(for:type)
            let name="\(id).\(suffix)"
            let destination=try store.outboxURL(name:name,configuration:configuration)
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try FileManager.default.copyItem(at:attachment,to:destination)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
            attachmentName=name; mediaType=type; copiedURL=destination
        }
        var next=replica
        next.outbox.append(OutgoingMessage(id:id,body:body,localAttachmentName:attachmentName,mediaType:mediaType))
        do { try commit(next,configuration:configuration) }
        catch { if let copiedURL { try? FileManager.default.removeItem(at:copiedURL) }; throw error }
        Task { [weak self] in await self?.refresh() }
        return id
    }

    func discardOutgoing(id: String) throws {
        guard let configuration else { throw MessageServiceError.notConfigured }
        let item=replica.outbox.first { $0.id == id }
        var next=replica; next.outbox.removeAll { $0.id == id }
        try commit(next,configuration:configuration)
        if let name=item?.localAttachmentName, let url=try? store.outboxURL(name:name,configuration:configuration) { try? FileManager.default.removeItem(at:url) }
    }

    func markRead(_ message: ChatMessage) throws {
        guard let configuration else { throw MessageServiceError.notConfigured }
        guard message.belongs(to:configuration.identity), message.recipientID == configuration.deviceID,
              let index=replica.messages.firstIndex(where:{ $0.id == message.id }) else { throw MessageServiceError.invalidMessage }
        guard replica.messages[index].readAt == nil else { return }
        var next=replica; next.messages[index].readAt=Date()
        if !next.pendingReadIDs.contains(message.id) { next.pendingReadIDs.append(message.id) }
        try commit(next,configuration:configuration)
        Task { [weak self] in await self?.refresh() }
    }

    /// Call this before presenting a viewer. A download or checksum failure never
    /// marks a message read; the UI calls markRead only after successful display.
    func attachmentURL(for message: ChatMessage) async throws -> URL? {
        guard let configuration else { throw MessageServiceError.notConfigured }
        guard message.belongs(to:configuration.identity), message.isValid else { throw MessageServiceError.invalidMessage }
        guard let attachment=message.attachment else { return nil }
        let destination=try store.cacheURL(attachment:attachment,configuration:configuration)
        if FileManager.default.fileExists(atPath:destination.path), try verify(destination,attachment:attachment) { return destination }
        let token=try credential(for:configuration), operation=generation
        let request=try makeRequest("GET",path:"v1/attachments/\(attachment.id)",server:configuration.serverURL,token:token)
        let (temporary,response)=try await session.download(for:request)
        defer { try? FileManager.default.removeItem(at:temporary) }
        try check(response)
        guard operation == generation else { throw CancellationError() }
        guard try verify(temporary,attachment:attachment) else { throw MessageServiceError.invalidResponse }
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        if FileManager.default.fileExists(atPath:destination.path) { try FileManager.default.removeItem(at:destination) }
        try FileManager.default.copyItem(at:temporary,to:destination)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
        return destination
    }

    private func synchronize(force: Bool) async {
        guard let configuration, historyLoaded, synchronizingGeneration == nil, force || Date()>=retryAt else { return }
        let operation=generation
        synchronizingGeneration=operation
        defer { if synchronizingGeneration == operation { synchronizingGeneration=nil } }
        do {
            let token=try credential(for:configuration)
            while let item=replica.outbox.first {
                try Task.checkCancellation()
                var uploaded=item.uploadedAttachment
                if uploaded == nil, let name=item.localAttachmentName, let mediaType=item.mediaType {
                    let file=try store.outboxURL(name:name,configuration:configuration)
                    guard FileManager.default.fileExists(atPath:file.path) else { throw MessageServiceError.missingAttachment }
                    var request=try makeRequest("POST",path:"v1/attachments",server:configuration.serverURL,token:token)
                    request.setValue(mediaType,forHTTPHeaderField:"Content-Type")
                    request.setValue(item.id,forHTTPHeaderField:"X-Client-Upload-ID")
                    let (bytes,response)=try await session.upload(for:request,fromFile:file)
                    try check(response)
                    guard operation == generation else { throw CancellationError() }
                    let descriptor=try MessagingJSON.decoder().decode(ChatAttachment.self,from:bytes)
                    guard descriptor.isValid, descriptor.mediaType == mediaType else { throw MessageServiceError.invalidResponse }
                    var next=replica
                    guard let index=next.outbox.firstIndex(where:{ $0.id == item.id }) else { continue }
                    next.outbox[index].uploadedAttachment=descriptor
                    try commit(next,configuration:configuration); uploaded=descriptor
                }
                struct Send: Encodable { let clientRequestID: String; let body: RichMessageBody; let attachmentID: String? }
                let data=try MessagingJSON.encoder().encode(Send(clientRequestID:item.id,body:item.body,attachmentID:uploaded?.id))
                let message: ChatMessage=try await jsonRequest("POST",path:"v1/messages",server:configuration.serverURL,token:token,body:data)
                guard operation == generation else { throw CancellationError() }
                guard message.isValid, message.belongs(to:configuration.identity), message.senderID == configuration.deviceID,
                      message.clientRequestID == item.id, message.body == item.body, message.attachment?.id == uploaded?.id else { throw MessageServiceError.invalidResponse }
                var next=replica; next.upsert(message); next.outbox.removeAll { $0.id == item.id }
                try commit(next,configuration:configuration)
                if let name=item.localAttachmentName, let url=try? store.outboxURL(name:name,configuration:configuration) { try? FileManager.default.removeItem(at:url) }
            }
            for id in replica.pendingReadIDs {
                try Task.checkCancellation()
                let message: ChatMessage=try await jsonRequest("PUT",path:"v1/messages/\(id)/read",server:configuration.serverURL,token:token)
                guard operation == generation else { throw CancellationError() }
                guard message.isValid, message.belongs(to:configuration.identity), message.id == id,
                      message.recipientID == configuration.deviceID, message.readAt != nil else { throw MessageServiceError.invalidResponse }
                var next=replica; next.upsert(message); next.pendingReadIDs.removeAll { $0 == id }
                try commit(next,configuration:configuration)
            }
            for _ in 0..<100 {
                try Task.checkCancellation()
                let page: MessageSyncPage=try await jsonRequest("GET",path:"v1/sync",server:configuration.serverURL,token:token,
                                                               query:[URLQueryItem(name:"cursor",value:String(replica.cursor)),URLQueryItem(name:"limit",value:"100")])
                guard operation == generation else { throw CancellationError() }
                let next=try replica.applying(page,identity:configuration.identity)
                try commit(next,configuration:configuration)
                if !page.hasMore { break }
            }
            failureCount=0; retryAt = .distantPast; connectionStatus="Connected"; lastError=nil; notify()
        } catch {
            guard operation == generation, !(error is CancellationError) else { return }
            failureCount=min(8,failureCount+1)
            retryAt=Date().addingTimeInterval(min(60,pow(2,Double(failureCount))))
            lastError=error.localizedDescription; connectionStatus="Offline — retrying"; notify()
        }
    }

    private func commit(_ next: MessageReplica, configuration: MessageConfiguration) throws {
        try store.save(next,configuration:configuration)
        replica=next; notify()
    }
    private func notify() { onChange?() }
    private func credential(for configuration: MessageConfiguration) throws -> String {
        guard let token=try credentials.read(account:configuration.credentialAccount), !token.isEmpty else { throw MessageServiceError.credentials }
        return token
    }
    private func makeRequest(_ method: String, path: String, server: URL, token: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard Self.validServerURL(server) else { throw MessageServiceError.invalidConfiguration }
        var parts=URLComponents(url:server.appendingPathComponent(path),resolvingAgainstBaseURL:false)!
        if !query.isEmpty { parts.queryItems=query }
        var request=URLRequest(url:parts.url!)
        request.httpMethod=method; request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
    private func jsonRequest<T: Decodable>(_ method: String, path: String, server: URL, token: String,
                                            body: Data? = nil, query: [URLQueryItem] = []) async throws -> T {
        var request=try makeRequest(method,path:path,server:server,token:token,query:query)
        if let body { request.httpBody=body; request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        let (data,response)=try await session.data(for:request)
        try check(response)
        do { return try MessagingJSON.decoder().decode(T.self,from:data) }
        catch { throw MessageServiceError.invalidResponse }
    }
    private func check(_ response: URLResponse) throws {
        guard let http=response as? HTTPURLResponse else { throw MessageServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MessageServiceError.server(http.statusCode) }
    }
    private func verify(_ file: URL, attachment: ChatAttachment) throws -> Bool {
        let result=try MessageStore.fileDigest(file)
        return result.size == attachment.byteCount && result.sha256.lowercased() == attachment.sha256.lowercased()
    }
    private static func fileExtension(for type: String) -> String {
        switch type {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic","image/heif": return "heic"
        case "video/mp4": return "mp4"
        default: return "mov"
        }
    }
    nonisolated static func mediaType(of url: URL) throws -> String {
        let handle=try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        let bytes=try handle.read(upToCount:32) ?? Data(), data=[UInt8](bytes)
        if data.starts(with:[0xff,0xd8,0xff]) { return "image/jpeg" }
        if data.starts(with:[137,80,78,71,13,10,26,10]) { return "image/png" }
        if bytes.starts(with:Data("GIF87a".utf8)) || bytes.starts(with:Data("GIF89a".utf8)) { return "image/gif" }
        if data.count>=12, String(bytes:data[4..<8],encoding:.ascii) == "ftyp" {
            let brand=String(bytes:data[8..<12],encoding:.ascii) ?? ""
            if ["heic","heix","hevc","hevx","mif1","msf1"].contains(brand) { return "image/heic" }
            if brand == "qt  " { return "video/quicktime" }
            return "video/mp4"
        }
        if data.count>=8, ["wide","mdat","moov"].contains(String(bytes:data[4..<8],encoding:.ascii) ?? "") { return "video/quicktime" }
        throw MessageServiceError.unsupportedMedia
    }
}
