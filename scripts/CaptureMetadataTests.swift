import Foundation
import CoreGraphics
import ImageIO

@main
struct CaptureMetadataTests {
    static func main() throws {
        // スーパーだけでは字幕ありの二枚目やcaptionフラグを作らない。
        for mode in CaptureCaptionMode.allCases { precondition(mode.captionVariants(hasCaption: false) == [false]) }
        precondition(CaptureCaptionMode.videoOnly.captionVariants(hasCaption: true) == [false])
        precondition(CaptureCaptionMode.compositingCaption.captionVariants(hasCaption: true) == [true])
        precondition(CaptureCaptionMode.both.captionVariants(hasCaption: true) == [false, true])
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var metadata = CaptureMetadata(capturedAt: date, playbackPosition: 123.25,
            networkID: 32736, serviceID: 1024, eventID: nil, title: "日本語の番組・テスト😀",
            description: "番組説明\n二行目", startTime: "2023-11-15T00:00:00+09:00",
            endTime: "2023-11-15T00:30:00+09:00", duration: 1800)
        metadata.is_caption_composited = true
        let source = try makeJPEG()
        let jpeg = try CaptureJPEG.encode(source, metadata: metadata, capturedAt: date, software: "KonomiTV Viewer version test")
        precondition(Array(jpeg.prefix(4)) == [0xff, 0xd8, 0xff, 0xe1])
        let payloadLength = Int(jpeg[4]) << 8 | Int(jpeg[5])
        precondition(jpeg.subdata(in: 6..<12) == Data([69, 120, 105, 102, 0, 0]))
        let tiff = jpeg.subdata(in: 12..<(4 + payloadLength))
        precondition(tiff.prefix(4) == Data([0x49, 0x49, 0x2a, 0]))
        let root = directory(tiff, offset: Int(u32(tiff, 4)))
        precondition(root.count == 8)
        guard let xp = root[40092], let text = String(data: xp, encoding: .utf16LittleEndian),
              let utf8 = text.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: utf8) as? [String: Any]
        else { preconditionFailure("XPComment must be UTF-16LE JSON") }
        precondition(json["title"] as? String == metadata.title)
        precondition(json["description"] as? String == metadata.description)
        precondition(json["captured_playback_position"] as? Double == 123.25)
        precondition(json["event_id"] as? Int == -1)
        precondition(json["caption_text"] is NSNull)
        precondition(json["is_caption_composited"] as? Bool == true)
        precondition(json["is_comment_composited"] as? Bool == false)
        precondition(String(data: root[0x0131]!, encoding: .ascii) == "KonomiTV Viewer version test\0")
        let exif = directory(tiff, offset: Int(u32(root[0x8769]!, 0)))
        precondition(exif[0x9000] == Data("0230".utf8))
        precondition(exif[0x9003] == root[0x0132] && exif[0x9004] == root[0x0132])
        precondition(jpeg.suffix(from: 4 + payloadLength) == source.dropFirst(2))
        let imageSource = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
        precondition(decoded.width == 2 && decoded.height == 2)

        let invalid = CaptureMetadata(capturedAt: date, playbackPosition: .nan,
            networkID: -5, serviceID: 65536, eventID: nil, title: "", description: nil,
            startTime: "2023-11-15T00:00:00+09:00", endTime: "2023-11-15T00:00:00+09:00", duration: .infinity)
        precondition(invalid.captured_playback_position == 0 && invalid.duration == 0)
        precondition(invalid.network_id == -1 && invalid.service_id == -1)
        do {
            _ = try CaptureJPEG.encode(Data(), metadata: metadata, capturedAt: date, software: "test")
            preconditionFailure("Invalid JPEG must be rejected")
        } catch CaptureJPEG.Failure.invalidJPEG { }
        let enormous = CaptureMetadata(capturedAt: date, playbackPosition: 0, networkID: nil, serviceID: nil,
            eventID: nil, title: "test", description: String(repeating: "あ", count: 40000),
            startTime: "2023-11-15T00:00:00+09:00", endTime: "2023-11-15T00:00:00+09:00", duration: 0)
        do {
            _ = try CaptureJPEG.encode(source, metadata: enormous, capturedAt: date, software: "test")
            preconditionFailure("Oversized APP1 must not corrupt JPEG")
        } catch CaptureJPEG.Failure.metadataTooLarge { }
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "artifacts/ipa/capture-metadata-test.jpg")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: output)
        print("Capture metadata tests passed: XPComment, Unicode, flags, nulls, Exif, JPEG decoding, invalid and oversized inputs")
    }

    static func makeJPEG() throws -> Data {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }
    static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }
    static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(u16(data, offset)) | UInt32(u16(data, offset + 2)) << 16
    }
    // 本体writerとは独立したTIFF readerでtagとoffsetを照合する。
    static func directory(_ tiff: Data, offset: Int) -> [UInt16: Data] {
        var result: [UInt16: Data] = [:]
        for index in 0..<Int(u16(tiff, offset)) {
            let entry = offset + 2 + index * 12
            let tag = u16(tiff, entry)
            let type = u16(tiff, entry + 2)
            let size = Int(u32(tiff, entry + 4)) * (type == 3 ? 2 : (type == 4 ? 4 : (type == 5 ? 8 : 1)))
            let start = size <= 4 ? entry + 8 : Int(u32(tiff, entry + 8))
            result[tag] = tiff.subdata(in: start..<(start + size))
        }
        return result
    }
}
