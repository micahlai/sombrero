import Foundation
import CryptoKit
import PetCore

struct MessageConfiguration: Codable, Equatable {
    let serverURL: URL
    let identity: ChatIdentity
    let credentialAccount: String
    var deviceID: String { identity.deviceID }
    var peerID: String { identity.peerID }
    var pairID: String { identity.pairID }
}

final class MessageStore {
    let root: URL
    private let manager=FileManager.default
    init(root: URL? = nil, profile: String = "default") {
        let base=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
            .appendingPathComponent("WatercolorDuck/Messages",isDirectory:true)
        let safeProfile=Self.digest(Data(profile.utf8))
        self.root=base.appendingPathComponent(safeProfile,isDirectory:true)
    }
    private var configurationFile: URL { root.appendingPathComponent("configuration.json") }
    func loadConfiguration() throws -> MessageConfiguration? {
        guard manager.fileExists(atPath:configurationFile.path) else { return nil }
        let configuration=try MessagingJSON.decoder().decode(MessageConfiguration.self,from:Data(contentsOf:configurationFile))
        guard configuration.identity.isValid, !configuration.credentialAccount.isEmpty,
              MessageService.validServerURL(configuration.serverURL) else { throw MessageServiceError.invalidConfiguration }
        return configuration
    }
    func saveConfiguration(_ configuration: MessageConfiguration) throws {
        try write(MessagingJSON.encoder().encode(configuration),to:configurationFile)
    }
    func clearConfiguration() throws {
        if manager.fileExists(atPath:configurationFile.path) { try manager.removeItem(at:configurationFile) }
    }
    func partition(_ configuration: MessageConfiguration) -> URL {
        let key="\(configuration.serverURL.absoluteString)\u{0}\(configuration.pairID)\u{0}\(configuration.deviceID)"
        return root.appendingPathComponent(Self.digest(Data(key.utf8)),isDirectory:true)
    }
    func load(_ configuration: MessageConfiguration) throws -> MessageReplica {
        let file=partition(configuration).appendingPathComponent("replica.json")
        guard manager.fileExists(atPath:file.path) else { return MessageReplica() }
        let value=try MessagingJSON.decoder().decode(MessageReplica.self,from:Data(contentsOf:file))
        guard value.cursor >= 0, value.messages.allSatisfy({ $0.isValid && $0.belongs(to:configuration.identity) }),
              Set(value.messages.map(\.id)).count == value.messages.count,
              Set(value.outbox.map(\.id)).count == value.outbox.count,
              value.pendingReadIDs.allSatisfy({ UUID(uuidString:$0) != nil }),
              value.outbox.allSatisfy({ outgoing in
                  UUID(uuidString:outgoing.id) != nil && outgoing.body.isValid &&
                  (outgoing.localAttachmentName == nil || Self.safeLocalName(outgoing.localAttachmentName!)) &&
                  (outgoing.mediaType == nil || MessageMediaTypes.allowed.contains(outgoing.mediaType!)) &&
                  (outgoing.uploadedAttachment == nil || outgoing.uploadedAttachment!.isValid)
              }) else { throw MessageServiceError.invalidLocalHistory }
        return value
    }
    func save(_ replica: MessageReplica, configuration: MessageConfiguration) throws {
        try write(MessagingJSON.encoder().encode(replica),to:partition(configuration).appendingPathComponent("replica.json"))
    }
    func outboxURL(name: String, configuration: MessageConfiguration) throws -> URL {
        guard Self.safeLocalName(name) else { throw MessageServiceError.invalidLocalHistory }
        return partition(configuration).appendingPathComponent("outbox",isDirectory:true).appendingPathComponent(name)
    }
    func cacheURL(attachment: ChatAttachment, configuration: MessageConfiguration) throws -> URL {
        guard attachment.isValid else { throw MessageServiceError.invalidResponse }
        return partition(configuration).appendingPathComponent("media",isDirectory:true)
            .appendingPathComponent("\(attachment.id).\(attachment.fileExtension)")
    }
    func copyToOutbox(_ source: URL, id: String, mediaType: String, configuration: MessageConfiguration) throws -> String {
        let suffix=ChatAttachment(id:id,mediaType:mediaType,byteCount:1,sha256:String(repeating:"0",count:64),createdAt:Date()).fileExtension
        let name="\(id).\(suffix)", target=try outboxURL(name:name,configuration:configuration)
        try makeDirectory(target.deletingLastPathComponent())
        try manager.copyItem(at:source,to:target)
        try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
        return name
    }
    func cacheDownloaded(_ source: URL, attachment: ChatAttachment, configuration: MessageConfiguration) throws -> URL {
        let target=try cacheURL(attachment:attachment,configuration:configuration)
        try makeDirectory(target.deletingLastPathComponent())
        if manager.fileExists(atPath:target.path) { try manager.removeItem(at:target) }
        try manager.moveItem(at:source,to:target)
        try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
        return target
    }
    func removeOutgoingFile(_ outgoing: OutgoingMessage, configuration: MessageConfiguration) {
        guard let name=outgoing.localAttachmentName, let file=try? outboxURL(name:name,configuration:configuration) else { return }
        try? manager.removeItem(at:file)
    }
    private func write(_ data: Data, to file: URL) throws {
        try makeDirectory(file.deletingLastPathComponent())
        try data.write(to:file,options:.atomic)
        try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    private func makeDirectory(_ directory: URL) throws {
        try manager.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    }
    private static func safeLocalName(_ name: String) -> Bool {
        let pieces=name.split(separator:".",omittingEmptySubsequences:false)
        return pieces.count == 2 && UUID(uuidString:String(pieces[0])) != nil && ["jpg","png","gif","heic","mp4","mov"].contains(String(pieces[1]))
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    static func fileDigest(_ url: URL) throws -> (size: Int, sha256: String) {
        let handle=try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        var hash=SHA256(), count=0
        while let bytes=try handle.read(upToCount:128*1_024), !bytes.isEmpty { hash.update(data:bytes); count+=bytes.count }
        return (count,hash.finalize().map { String(format:"%02x",$0) }.joined())
    }
}
