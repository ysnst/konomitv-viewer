import Foundation

/// H.265 / HEVC 再生の経路で、アプリ内の中継が受け取った区切りファイル
/// (MPEG-TS) から、字幕の包みだけを取り出す。
///
/// 配信の区切りファイルには、映像・音声とは別の流れ (PID 0x103) で
/// 字幕データが入っている (research-subtitle-feasibility.md で実証済み)。
/// その流れの PES の中身は ID3 形式で、PRIV フレームの中身が
/// 「宛先名 aribb24.js + 区切りの 0 + 字幕の中身」という形。
/// ここでは字幕の中身 (先頭が 0x80 = 字幕、0x81 = 文字スーパー) と、
/// その包みの時刻印 (90kHz) を取り出す。
/// あわせて、区切り内での位置合わせに使う「区切りの先頭の映像の時刻印」
/// も、番組表 (PAT) と番組情報 (PMT) を読んで映像の流れを特定し、
/// その最初の時刻印として取り出す (research-subtitle-hevc-route.md)。
///
/// 使い方: 区切りファイル1つにつき1つ作り、届いたデータをそのまま
/// feed で流し込み、最後に finish を呼ぶ。取り出し結果は
/// captionPackets と videoFirstPTS に残る。
/// データの区切り位置は問わない (途中で切れていてもつないで読む)。
final class TSID3Extractor {
    /// 取り出した字幕の包み1つ分 (時刻印は 90kHz の生の値)。
    struct Packet {
        var pts90: Int64
        var payload: Data
    }

    /// 字幕の流れの PID (配信側で確認済みの固定値)。
    private static let captionPID = 0x103
    /// 映像とみなす流れの種類 (PMT の stream_type)。
    /// H.265 (0x24) と H.264 (0x1B) を中心に、映像系の値を広めに取る。
    private static let videoStreamTypes: Set<UInt8> = [0x02, 0x10, 0x1B, 0x24, 0x42, 0xEA]

    /// 取り出した字幕の包み (届いた順)。
    private(set) var captionPackets: [Packet] = []
    /// 区切りの先頭の映像の時刻印 (90kHz)。取れなければ nil。
    private(set) var videoFirstPTS: Int64?

    /// TS の包み (188バイト) に満たない端数の控え。
    private var leftover = Data()
    /// 番組表 (PAT) から読んだ PMT の PID。
    private var pmtPID: Int?
    /// PMT から読んだ映像の PID。
    private var videoPID: Int?
    /// 節 (PAT / PMT) の読みかけの控えと、その PID。
    private var sectionBuffer = Data()
    private var sectionPID: Int?
    /// 字幕の PES の読みかけ (次の PES が始まるか finish で確定する)。
    private var captionPES = Data()
    private var captionPESStarted = false
    /// 映像の最初の時刻印を読むための、映像 PES の頭の読みかけ。
    private var videoHead = Data()
    private var videoHeadStarted = false

    /// 届いたデータを流し込む。何度に分けて呼んでもよい。
    func feed(_ chunk: Data) {
        var data = leftover + chunk
        leftover = Data()
        // 同期バイト (0x47) の位置に合わせる。先頭がずれている場合は、
        // 188バイト先にも同期バイトがある位置を探す (範囲指定で部分的に
        // 届いた場合の立て直し)。
        guard let start = findSync(in: data) else {
            // 同期が見つからない端数は捨てる (次の塊で立て直す)。
            return
        }
        if start > 0 {
            data = Data(data.dropFirst(start))
        }
        var offset = 0
        while offset + 188 <= data.count {
            handlePacket(Data(data[offset..<(offset + 188)]))
            offset += 188
        }
        if offset < data.count {
            leftover = Data(data[offset...])
        }
    }

    /// 区切りファイルの終わり。読みかけの字幕 PES を確定させる。
    func finish() {
        flushCaptionPES()
    }

    // MARK: - TS の包みの振り分け

    private func findSync(in data: Data) -> Int? {
        guard !data.isEmpty else { return nil }
        if data[0] == 0x47 { return 0 }
        var index = 0
        while index < data.count {
            if data[index] == 0x47 {
                // 188バイト先も同期バイトなら、そこが包みの頭とみる。
                if index + 188 >= data.count || data[index + 188] == 0x47 {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    private func handlePacket(_ packet: Data) {
        guard packet.count == 188, packet[0] == 0x47 else { return }
        let pusi = (packet[1] >> 6) & 1 == 1
        let pid = (Int(packet[1] & 0x1F) << 8) | Int(packet[2])
        let afc = (packet[3] >> 4) & 3
        guard afc != 2 else { return }  // 中身が無い包み (適応フィールドのみ)
        var offset = 4
        if afc == 3 {
            offset += 1 + Int(packet[4])
        }
        guard offset < 188 else { return }
        let payload = Data(packet[offset...])

        if pid == 0 {
            feedSection(pid: pid, pusi: pusi, payload: payload) { [weak self] section in
                self?.parsePAT(section)
            }
        } else if let pmtPID, pid == pmtPID {
            feedSection(pid: pid, pusi: pusi, payload: payload) { [weak self] section in
                self?.parsePMT(section)
            }
        } else if pid == Self.captionPID {
            if pusi {
                flushCaptionPES()
                captionPES = payload
                captionPESStarted = true
            } else if captionPESStarted {
                captionPES.append(payload)
            }
        } else if let videoPID, pid == videoPID, videoFirstPTS == nil {
            if pusi {
                videoHead = payload
                videoHeadStarted = true
            } else if videoHeadStarted {
                videoHead.append(payload)
            }
            if videoHeadStarted, videoHead.count >= 14 {
                videoFirstPTS = parsePESHeader(videoHead)?.pts
                videoHeadStarted = false
                videoHead = Data()
            }
        }
    }

    /// 節 (PAT / PMT) は短いので、長さがそろうまでつないでから渡す。
    private func feedSection(pid: Int, pusi: Bool, payload: Data, onComplete: (Data) -> Void) {
        if pusi {
            sectionPID = pid
            sectionBuffer = Data()
            // 先頭は pointer_field (その長さだけ飛ばした所から節が始まる)。
            guard !payload.isEmpty else { return }
            let pointer = Int(payload[0])
            guard payload.count > 1 + pointer else { return }
            sectionBuffer = Data(payload[(1 + pointer)...])
        } else {
            guard sectionPID == pid else { return }
            sectionBuffer.append(payload)
        }
        guard sectionBuffer.count >= 3 else { return }
        let sectionLength = (Int(sectionBuffer[1] & 0x0F) << 8) | Int(sectionBuffer[2])
        let total = 3 + sectionLength
        if sectionBuffer.count >= total {
            let section = Data(sectionBuffer[..<total])
            sectionBuffer = Data()
            sectionPID = nil
            onComplete(section)
        }
    }

    // MARK: - PAT / PMT の読み解き

    private func parsePAT(_ section: Data) {
        guard pmtPID == nil, section.count >= 12, section[0] == 0x00 else { return }
        let sectionLength = (Int(section[1] & 0x0F) << 8) | Int(section[2])
        let entriesEnd = min(section.count, 3 + sectionLength - 4)  // 末尾の CRC を除く
        var offset = 8
        while offset + 4 <= entriesEnd {
            let programNumber = (Int(section[offset]) << 8) | Int(section[offset + 1])
            let pid = (Int(section[offset + 2] & 0x1F) << 8) | Int(section[offset + 3])
            if programNumber != 0 {
                pmtPID = pid
                return
            }
            offset += 4
        }
    }

    private func parsePMT(_ section: Data) {
        guard videoPID == nil, section.count >= 12, section[0] == 0x02 else { return }
        let sectionLength = (Int(section[1] & 0x0F) << 8) | Int(section[2])
        let entriesEnd = min(section.count, 3 + sectionLength - 4)
        let programInfoLength = (Int(section[10] & 0x0F) << 8) | Int(section[11])
        var offset = 12 + programInfoLength
        while offset + 5 <= entriesEnd {
            let streamType = section[offset]
            let pid = (Int(section[offset + 1] & 0x1F) << 8) | Int(section[offset + 2])
            let esInfoLength = (Int(section[offset + 3] & 0x0F) << 8) | Int(section[offset + 4])
            if Self.videoStreamTypes.contains(streamType) {
                videoPID = pid
                return
            }
            offset += 5 + esInfoLength
        }
    }

    // MARK: - PES と ID3 の読み解き

    /// PES の頭を読み、時刻印と中身の開始位置を返す。
    /// 時刻印が無い PES (private_stream_2 等) では pts が nil になる。
    private func parsePESHeader(_ pes: Data) -> (pts: Int64?, payloadStart: Int)? {
        guard pes.count >= 9,
              pes[0] == 0x00, pes[1] == 0x00, pes[2] == 0x01 else { return nil }
        let streamID = pes[3]
        if streamID == 0xBF {
            // private_stream_2: 標準の頭が無い形 (この配信では使われない)。
            return (nil, 6)
        }
        let flags = pes[7]
        let headerLength = Int(pes[8])
        var pts: Int64?
        if flags & 0x80 != 0, pes.count >= 14 {
            let p = [UInt8](pes[9..<14])
            pts = (Int64(p[0] >> 1 & 0x07) << 30)
                | (Int64(p[1]) << 22)
                | (Int64(p[2] >> 1 & 0x7F) << 15)
                | (Int64(p[3]) << 7)
                | Int64(p[4] >> 1 & 0x7F)
        }
        return (pts, 9 + headerLength)
    }

    /// 読みかけの字幕 PES を確定させ、ID3 の PRIV フレームから
    /// 字幕の中身を取り出して控える。
    private func flushCaptionPES() {
        guard captionPESStarted else { return }
        captionPESStarted = false
        let pes = captionPES
        captionPES = Data()
        guard let header = parsePESHeader(pes),
              let pts = header.pts,
              pes.count > header.payloadStart else { return }
        let start = header.payloadStart
        let payload = Data(pes[start...])
        if let caption = extractID3PrivateData(payload) {
            captionPackets.append(Packet(pts90: pts, payload: caption))
        }
    }

    /// ID3 タグの中の最初の PRIV フレームから、宛先名の後ろにある
    /// 字幕の中身を取り出す。形が合わなければ nil。
    private func extractID3PrivateData(_ data: Data) -> Data? {
        guard data.count >= 10,
              data[0] == 0x49, data[1] == 0x44, data[2] == 0x33  // "ID3"
        else { return nil }
        let version = data[3]
        var tagSize = 0
        for index in 6..<10 {
            tagSize = (tagSize << 7) | Int(data[index] & 0x7F)
        }
        let tagEnd = min(data.count, 10 + tagSize)
        var offset = 10
        while offset + 10 <= tagEnd {
            let frameID = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            if frameID.hasPrefix("\0") { break }
            let frameSize: Int
            if version >= 4 {
                var value = 0
                for index in 0..<4 {
                    value = (value << 7) | Int(data[offset + 4 + index] & 0x7F)
                }
                frameSize = value
            } else {
                var value = 0
                for index in 0..<4 {
                    value = (value << 8) | Int(data[offset + 4 + index])
                }
                frameSize = value
            }
            let bodyStart = offset + 10
            guard frameSize >= 0, bodyStart + frameSize <= data.count else { return nil }
            if frameID == "PRIV" {
                let body = Data(data[bodyStart..<(bodyStart + frameSize)])
                // 宛先名は 0 で区切られ、その後ろが字幕の中身。
                guard let separator = body.firstIndex(of: 0),
                      body.count > separator + 1 else { return nil }
                return Data(body[(separator + 1)...])
            }
            offset = bodyStart + frameSize
        }
        return nil
    }
}
