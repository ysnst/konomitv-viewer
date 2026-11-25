import Foundation

// 保存する値は本家PWAと共有する。BrowserだけはブラウザDLの代わりに写真ライブラリを使う。
enum CaptureSaveMode: String, CaseIterable, Sendable {
    case browser = "Browser", uploadServer = "UploadServer", both = "Both"
    var title: String {
        switch self {
        case .browser: return "端末の写真ライブラリに保存"
        case .uploadServer: return "KonomiTVサーバーにアップロード"
        case .both: return "端末とKonomiTVサーバーの両方に保存"
        }
    }
}
enum CaptureCaptionMode: String, CaseIterable, Sendable {
    case videoOnly = "VideoOnly", compositingCaption = "CompositingCaption", both = "Both"
    var title: String {
        switch self {
        case .videoOnly: return "字幕を合成しない"
        case .compositingCaption: return "字幕を合成する"
        case .both: return "字幕なし・ありの両方"
        }
    }
}

/// 本家CaptureScanTaskがXPComment(tag 40092)から読む番組情報。映像秒は番組開始基準へ変換して渡す。
struct CaptureMetadata: Encodable, Sendable {
    let captured_at: String
    let captured_playback_position: Double
    let network_id: Int
    let service_id: Int
    let event_id: Int
    let title: String
    let description: String
    let start_time: String
    let end_time: String
    let duration: Double
    // 字幕エンジンは画像のみ公開するため、検索用本文は推測せずnullを記録する。
    let caption_text: String? = nil
    var is_caption_composited = false
    var is_comment_composited = false

    init(capturedAt: Date, playbackPosition: Double, networkID: Int?, serviceID: Int?, eventID: Int?,
         title: String, description: String?, startTime: String, endTime: String, duration: Double) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        captured_at = formatter.string(from: capturedAt)
        captured_playback_position = playbackPosition.isFinite ? playbackPosition : 0
        func identifier(_ value: Int?) -> Int { value.flatMap { (-1...65535).contains($0) ? $0 : nil } ?? -1 }
        network_id = identifier(networkID)
        service_id = identifier(serviceID)
        event_id = identifier(eventID)
        self.title = title
        self.description = description ?? ""
        start_time = startTime
        end_time = endTime
        self.duration = duration.isFinite ? max(0, duration) : 0
    }

    // Optionalの自動encodeはnilキーを省く。本家の必須nullフィールドを明示して互換を保つ。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(captured_at, forKey: .captured_at)
        try container.encode(captured_playback_position, forKey: .captured_playback_position)
        try container.encode(network_id, forKey: .network_id)
        try container.encode(service_id, forKey: .service_id)
        try container.encode(event_id, forKey: .event_id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(start_time, forKey: .start_time)
        try container.encode(end_time, forKey: .end_time)
        try container.encode(duration, forKey: .duration)
        try container.encodeNil(forKey: .caption_text)
        try container.encode(is_caption_composited, forKey: .is_caption_composited)
        try container.encode(is_comment_composited, forKey: .is_comment_composited)
    }
    private enum CodingKeys: String, CodingKey {
        case captured_at, captured_playback_position, network_id, service_id, event_id, title, description
        case start_time, end_time, duration, caption_text, is_caption_composited, is_comment_composited
    }
}

/// ImageIOに公開キーのないXPCommentを、標準TIFF/Exif APP1としてJPEGへ追加する。
/// ピクセルは再圧縮しない。offsetはTIFFヘッダー基準、XPCommentは本家と同じUTF-16LE。
enum CaptureJPEG {
    enum Failure: Error { case invalidJPEG, metadataTooLarge }
    private struct Entry {
        let tag: UInt16
        let type: UInt16
        let count: UInt32
        let bytes: Data
    }
    private static func little<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    private static func ascii(_ value: String) -> Data { Data(value.utf8) + Data([0]) }

    static func encode(_ jpeg: Data, metadata: CaptureMetadata, capturedAt: Date, software: String) throws -> Data {
        guard jpeg.count >= 2, jpeg.starts(with: [0xff, 0xd8]) else { throw Failure.invalidJPEG }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(metadata)
        guard let text = String(data: json, encoding: .utf8), let xpComment = text.data(using: .utf16LittleEndian) else {
            throw Failure.metadataTooLarge
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let date = ascii(formatter.string(from: capturedAt))
        let exif: [Entry] = [
            Entry(tag: 0x9000, type: 7, count: 4, bytes: Data("0230".utf8)),
            Entry(tag: 0x9003, type: 2, count: UInt32(date.count), bytes: date),
            Entry(tag: 0x9004, type: 2, count: UInt32(date.count), bytes: date),
            Entry(tag: 0x9101, type: 7, count: 4, bytes: Data([1, 2, 3, 0])),
            Entry(tag: 0xa000, type: 7, count: 4, bytes: Data("0100".utf8)),
            Entry(tag: 0xa001, type: 3, count: 1, bytes: little(UInt16(1))),
        ]
        let softwareBytes = ascii(software)
        let rational = little(UInt32(72)) + little(UInt32(1))
        // IFD0は8件。続くExif IFDの位置は可変データより前に固定する。
        let exifOffset = UInt32(8 + 2 + 8 * 12 + 4)
        let root: [Entry] = [
            Entry(tag: 0x011a, type: 5, count: 1, bytes: rational),
            Entry(tag: 0x011b, type: 5, count: 1, bytes: rational),
            Entry(tag: 0x0128, type: 3, count: 1, bytes: little(UInt16(2))),
            Entry(tag: 0x0131, type: 2, count: UInt32(softwareBytes.count), bytes: softwareBytes),
            Entry(tag: 0x0132, type: 2, count: UInt32(date.count), bytes: date),
            Entry(tag: 0x0213, type: 3, count: 1, bytes: little(UInt16(1))),
            Entry(tag: 0x8769, type: 4, count: 1, bytes: little(exifOffset)),
            Entry(tag: 40092, type: 1, count: UInt32(xpComment.count), bytes: xpComment),
        ]
        var variable = Data()
        let variableOffset = Int(exifOffset) + 2 + exif.count * 12 + 4
        func directory(_ entries: [Entry]) -> Data {
            var result = little(UInt16(entries.count))
            for entry in entries.sorted(by: { $0.tag < $1.tag }) {
                result += little(entry.tag) + little(entry.type) + little(entry.count)
                if entry.bytes.count <= 4 {
                    result += entry.bytes + Data(repeating: 0, count: 4 - entry.bytes.count)
                } else {
                    result += little(UInt32(variableOffset + variable.count))
                    variable += entry.bytes
                    if variable.count % 2 != 0 { variable.append(0) }
                }
            }
            return result + little(UInt32(0))
        }
        let rootDirectory = directory(root)
        let exifDirectory = directory(exif)
        let tiff = Data([0x49, 0x49, 0x2a, 0]) + little(UInt32(8)) + rootDirectory + exifDirectory + variable
        let payload = Data([0x45, 0x78, 0x69, 0x66, 0, 0]) + tiff
        guard payload.count <= 65533 else { throw Failure.metadataTooLarge }
        var length = UInt16(payload.count + 2).bigEndian
        let segment = Data([0xff, 0xe1]) + withUnsafeBytes(of: &length) { Data($0) } + payload
        return Data(jpeg.prefix(2)) + segment + jpeg.dropFirst(2)
    }
}
