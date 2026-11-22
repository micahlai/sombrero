import Foundation

public struct RichTextRun: Codable, Equatable {
    public let text: String
    public let bold: Bool
    public let italic: Bool
    public let underline: Bool
    public init(text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
        self.text=text; self.bold=bold; self.italic=italic; self.underline=underline
    }
    private enum CodingKeys: String, CodingKey { case text, bold, italic, underline }
    public init(from decoder: Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        text=try values.decode(String.self,forKey:.text)
        bold=try values.decodeIfPresent(Bool.self,forKey:.bold) ?? false
        italic=try values.decodeIfPresent(Bool.self,forKey:.italic) ?? false
        underline=try values.decodeIfPresent(Bool.self,forKey:.underline) ?? false
    }
}

public struct RichMessageBody: Codable, Equatable {
    public let version: Int
    public let runs: [RichTextRun]
    public init(runs: [RichTextRun], version: Int = 1) { self.version=version; self.runs=runs }
    public init(text: String) { self.init(runs:text.isEmpty ? [] : [RichTextRun(text:text)]) }
    public var plainText: String { runs.map(\.text).joined() }
    public var isValid: Bool {
        version == 1 && runs.count <= 1_000 && runs.reduce(0) { $0+$1.text.unicodeScalars.count } <= 20_000
    }
}

public struct ChatAttachment: Codable, Equatable, Identifiable {
    public let id: String
    public let mediaType: String
    public let byteCount: Int
    public let sha256: String
    public let createdAt: Date
    public init(id: String, mediaType: String, byteCount: Int, sha256: String, createdAt: Date) {
        self.id=id; self.mediaType=mediaType; self.byteCount=byteCount; self.sha256=sha256; self.createdAt=createdAt
    }
    public var isVideo: Bool { mediaType.hasPrefix("video/") }
    public var fileExtension: String {
        switch mediaType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic", "image/heif": return "heic"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        default: return "bin"
        }
    }
    public var isValid: Bool {
        UUID(uuidString:id) != nil && MessageMediaTypes.allowed.contains(mediaType) && byteCount > 0 &&
        byteCount <= (isVideo ? MessageMediaTypes.maximumVideoBytes : MessageMediaTypes.maximumImageBytes) &&
        sha256.count == 64 && sha256.allSatisfy { $0.isHexDigit && $0.isASCII }
    }
}

public enum MessageMediaTypes {
    public static let maximumImageBytes = 10*1_024*1_024
    public static let maximumVideoBytes = 100*1_024*1_024
    public static let allowed: Set<String> = ["image/jpeg","image/png","image/gif","image/heic","image/heif","video/mp4","video/quicktime"]
}

public struct ChatIdentity: Codable, Equatable {
    public let deviceID: String
    public let peerID: String
    public let pairID: String
    public init(deviceID: String, peerID: String, pairID: String) { self.deviceID=deviceID; self.peerID=peerID; self.pairID=pairID }
    public var isValid: Bool {
        UUID(uuidString:deviceID) != nil && UUID(uuidString:peerID) != nil && UUID(uuidString:pairID) != nil && deviceID != peerID
    }
}

public struct ChatMessage: Codable, Equatable, Identifiable {
    public let id: String
    public let pairID: String
    public let senderID: String
    public var senderName: String?
    public let recipientID: String
    public let clientRequestID: String
    public let body: RichMessageBody
    public let attachment: ChatAttachment?
    public let createdAt: Date
    public var readAt: Date?
    public init(id: String, pairID: String, senderID: String, recipientID: String, clientRequestID: String,
                body: RichMessageBody, attachment: ChatAttachment?, createdAt: Date, readAt: Date? = nil, senderName: String? = nil) {
        self.id=id; self.pairID=pairID; self.senderID=senderID; self.recipientID=recipientID
        self.clientRequestID=clientRequestID; self.body=body; self.attachment=attachment; self.createdAt=createdAt; self.readAt=readAt
        self.senderName=senderName
    }
    public var displaySenderName: String? {
        guard let senderName else { return nil }
        let name=senderName.split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
        return name.isEmpty ? nil : String(name.prefix(80))
    }
    public func belongs(to identity: ChatIdentity) -> Bool {
        identity.isValid && pairID == identity.pairID &&
        ((senderID == identity.deviceID && recipientID == identity.peerID) ||
         (senderID == identity.peerID && recipientID == identity.deviceID))
    }
    public var isValid: Bool {
        UUID(uuidString:id) != nil && UUID(uuidString:clientRequestID) != nil && body.isValid &&
        (!body.plainText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || attachment != nil) &&
        (attachment == nil || attachment!.isValid)
    }
}

public struct MessageChange: Codable, Equatable {
    public let sequence: Int
    public let type: String
    public let message: ChatMessage
    public init(sequence: Int, type: String, message: ChatMessage) { self.sequence=sequence; self.type=type; self.message=message }
}

public struct MessageSyncPage: Codable, Equatable {
    public let cursor: Int
    public let hasMore: Bool
    public let changes: [MessageChange]
    public init(cursor: Int, hasMore: Bool, changes: [MessageChange]) { self.cursor=cursor; self.hasMore=hasMore; self.changes=changes }
}

public struct OutgoingMessage: Codable, Equatable, Identifiable {
    public let id: String
    public let body: RichMessageBody
    public let createdAt: Date
    public let localAttachmentName: String?
    public let mediaType: String?
    public var uploadedAttachment: ChatAttachment?
    public init(id: String = UUID().uuidString.lowercased(), body: RichMessageBody, createdAt: Date = Date(),
                localAttachmentName: String? = nil, mediaType: String? = nil, uploadedAttachment: ChatAttachment? = nil) {
        self.id=id; self.body=body; self.createdAt=createdAt; self.localAttachmentName=localAttachmentName
        self.mediaType=mediaType; self.uploadedAttachment=uploadedAttachment
    }
}

/// Saving this value atomically commits messages and their cursor together.
public struct MessageReplica: Codable, Equatable {
    public var cursor: Int = 0
    public var messages: [ChatMessage] = []
    public var outbox: [OutgoingMessage] = []
    public var pendingReadIDs: [String] = []
    public init() {}
    public func applying(_ page: MessageSyncPage, identity: ChatIdentity) throws -> MessageReplica {
        guard page.cursor >= cursor, page.changes.count <= 100 else { throw MessageValidationError.invalidSync }
        var last=cursor
        for change in page.changes {
            guard change.sequence > last, change.sequence <= page.cursor, ["message","read"].contains(change.type),
                  change.message.isValid, change.message.belongs(to:identity) else { throw MessageValidationError.invalidSync }
            last=change.sequence
        }
        guard !page.hasMore || (page.cursor > cursor && !page.changes.isEmpty) else { throw MessageValidationError.invalidSync }
        var copy=self
        for change in page.changes { copy.upsert(change.message) }
        copy.cursor=page.cursor
        return copy
    }
    public mutating func upsert(_ message: ChatMessage) {
        var value=message
        if let index=messages.firstIndex(where: { $0.id == value.id }) {
            // Read state is monotonic, including receipts queued while offline.
            if value.readAt == nil { value.readAt=messages[index].readAt }
            if value.senderName == nil { value.senderName=messages[index].senderName }
            messages[index]=value
        } else { messages.append(value) }
        messages.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }
}

public enum MessageValidationError: Error { case invalidSync }

public enum MessagingJSON {
    public static func decoder() -> JSONDecoder {
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text=try decoder.singleValueContainer().decode(String.self)
            let formatter=ISO8601DateFormatter(); formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            if let value=formatter.date(from:text) { return value }
            formatter.formatOptions=[.withInternetDateTime]
            if let value=formatter.date(from:text) { return value }
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid message timestamp"))
        }
        return decoder
    }
    public static func encoder() -> JSONEncoder {
        let encoder=JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter=ISO8601DateFormatter(); formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            var container=encoder.singleValueContainer(); try container.encode(formatter.string(from:date))
        }
        encoder.outputFormatting=[.sortedKeys]
        return encoder
    }
}
