import Foundation
import CryptoKit
import PetCore

struct MessageDraft {
    let body: RichMessageBody
    let attachment: URL?
}

/// An unsent draft belongs to one server/pair/device, just like the outbox.
/// Copy attachments into private storage so closing/relaunching cannot lose a
/// temporary camera file or depend on a file remaining in Downloads.
final class MessageDraftStore {
    private struct Saved: Codable {
        let body: RichMessageBody
        let attachmentName: String?
        let originalURL: URL?
    }
    private let root: URL
    private let manager=FileManager.default
    private var file: URL { root.appendingPathComponent("draft.json") }
    init(profile: String, directory: URL? = nil) {
        let base=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
            .appendingPathComponent("WatercolorDuck/MessageDrafts",isDirectory:true)
        let key=SHA256.hash(data:Data(profile.utf8)).map { String(format:"%02x",$0) }.joined()
        root=base.appendingPathComponent(key,isDirectory:true)
    }
    func load() throws -> MessageDraft? {
        guard let saved=try read() else { return nil }
        return MessageDraft(body:saved.body,attachment:try localURL(saved.attachmentName))
    }
    func save(body: RichMessageBody, attachment: URL?) throws {
        guard body.isValid else { throw MessageServiceError.invalidMessage }
        let previous=try read()
        try manager.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var attachmentName: String?
        var copied: URL?
        if let attachment {
            guard attachment.isFileURL else { throw MessageServiceError.invalidMessage }
            if let previous, let existing=try localURL(previous.attachmentName),
               (previous.originalURL?.standardizedFileURL.path == attachment.standardizedFileURL.path || existing.standardizedFileURL.path == attachment.standardizedFileURL.path),
               manager.fileExists(atPath:existing.path) {
                attachmentName=previous.attachmentName
            } else {
                let suffix=attachment.pathExtension.lowercased()
                guard ["jpg","jpeg","png","gif","heic","heif","mp4","mov"].contains(suffix) else { throw MessageServiceError.invalidMessage }
                let size=try attachment.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
                let limit=["mp4","mov"].contains(suffix) ? MessageMediaTypes.maximumVideoBytes : MessageMediaTypes.maximumImageBytes
                guard size.isRegularFile == true, let count=size.fileSize, count>0 else { throw MessageServiceError.unsupportedMedia }
                guard count<=limit else { throw MessageServiceError.mediaTooLarge }
                attachmentName="\(UUID().uuidString.lowercased()).\(suffix)"
                let target=root.appendingPathComponent(attachmentName!)
                try manager.copyItem(at:attachment,to:target); copied=target
                try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
            }
        }
        do {
            let data=try JSONEncoder().encode(Saved(body:body,attachmentName:attachmentName,originalURL:attachment))
            try data.write(to:file,options:.atomic)
            try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        } catch {
            if let copied { try? manager.removeItem(at:copied) }
            throw error
        }
        if let old=previous?.attachmentName, old != attachmentName, let url=try localURL(old) { try? manager.removeItem(at:url) }
    }
    func clear() {
        if let saved=try? read(), let url=try? localURL(saved.attachmentName) { try? manager.removeItem(at:url) }
        try? manager.removeItem(at:file)
    }
    private func read() throws -> Saved? {
        guard manager.fileExists(atPath:file.path) else { return nil }
        let saved=try JSONDecoder().decode(Saved.self,from:Data(contentsOf:file))
        guard saved.body.isValid else { throw MessageServiceError.invalidLocalHistory }
        _ = try localURL(saved.attachmentName)
        return saved
    }
    private func localURL(_ name: String?) throws -> URL? {
        guard let name else { return nil }
        guard !name.contains("/"), !name.contains(".."), UUID(uuidString:URL(fileURLWithPath:name).deletingPathExtension().lastPathComponent) != nil else {
            throw MessageServiceError.invalidLocalHistory
        }
        return root.appendingPathComponent(name)
    }
}
