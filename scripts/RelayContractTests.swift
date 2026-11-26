import Foundation

private enum ContractError: Error { case failed(String) }
private func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw ContractError.failed(message) }
}

/// 最初の受信後に実クライアントを取り消し、上流の長い接続も終了するか調べる。
private final class CancelAfterData: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Int, Error>?
    private var received = 0
    init(_ continuation: CheckedContinuation<Int, Error>) { self.continuation = continuation }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received += data.count
        dataTask.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.invalidateAndCancel()
        guard let continuation else { return }
        self.continuation = nil
        if received > 0 { continuation.resume(returning: received) }
        else { continuation.resume(throwing: error ?? ContractError.failed("No streaming bytes received")) }
    }
}

@main
private struct RelayContractTests {
    static let headers = ["CF-Access-Client-Id": "relay-contract-client", "CF-Access-Client-Secret": "relay-contract-secret"]
    @MainActor static func mapped(_ url: URL) async throws -> URL {
        let relay = await withCheckedContinuation { continuation in
            StreamRelayServer.shared.relayURL(for: url) { continuation.resume(returning: $0) }
        }
        guard let relay else { throw ContractError.failed("Relay listener did not become ready") }
        return relay
    }
    static func fetch(_ url: URL, range: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ContractError.failed("Missing HTTP response") }
        return (data, http)
    }
    static func main() {
        Task { @MainActor in
            do {
                try await run()
                print("Relay contract tests passed: CF headers, 200/206/416, relative/MAP URIs, stream cancellation and reuse")
                exit(0)
            } catch {
                fputs("Relay contract failure: \(error)\n", stderr)
                exit(1)
            }
        }
        dispatchMain()
    }
    @MainActor static func run() async throws {
        guard CommandLine.arguments.count == 2, let base = URL(string: CommandLine.arguments[1]) else {
            throw ContractError.failed("Expected fixture base URL")
        }
        let bytes = Data((0..<1024).map { UInt8($0 % 256) })
        SettingsStore.shared.configure(base: base, headers: [:])
        let resource = try await mapped(base.appendingPathComponent("media/segment.bin"))
        print("RELAY_PORT=\(resource.port!)")
        try require(resource.host == "127.0.0.1" && resource.port != base.port, "Request bypassed relay")
        let (unauthorized, missingAuth) = try await fetch(resource)
        try require(missingAuth.statusCode == 401 && unauthorized.isEmpty, "Missing credentials did not remain a 401")

        SettingsStore.shared.configure(base: base, headers: headers)
        let (full, fullResponse) = try await fetch(resource)
        try require(fullResponse.statusCode == 200 && full == bytes, "Authenticated full response mismatch")
        let (part, partial) = try await fetch(resource, range: "bytes=10-19")
        try require(partial.statusCode == 206 && part == bytes.subdata(in: 10..<20), "Range request or body changed")
        try require(partial.value(forHTTPHeaderField: "Content-Range") == "bytes 10-19/1024", "Content-Range changed")
        let (empty, outOfRange) = try await fetch(resource, range: "bytes=4096-")
        try require(outOfRange.statusCode == 416 && empty.isEmpty, "Unsatisfiable range lost status")
        try require(outOfRange.value(forHTTPHeaderField: "Content-Range") == "bytes */1024", "416 Content-Range changed")

        let playlist = try await mapped(base.appendingPathComponent("media/master.m3u8"))
        let (body, playlistResponse) = try await fetch(playlist)
        try require(playlistResponse.statusCode == 200, "Playlist request failed")
        let text = String(decoding: body, as: UTF8.self)
        let lines = text.components(separatedBy: "\n")
        guard let mapLine = lines.first(where: { $0.hasPrefix("#EXT-X-MAP:") }),
              let mapValue = mapLine.components(separatedBy: "URI=\"").last?.components(separatedBy: "\"").first,
              let initURL = URL(string: mapValue),
              let segmentLine = lines.first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
              let segmentURL = URL(string: segmentLine) else {
            throw ContractError.failed("Playlist did not retain MAP and segment URI")
        }
        try require(initURL.host == resource.host && initURL.port == resource.port && initURL.path == "/media/init.bin", "MAP did not use relay")
        try require(segmentURL.host == resource.host && segmentURL.port == resource.port && segmentURL.path == "/media/segment.bin", "Relative segment did not use relay")
        try require(initURL.query == "asset=init" && segmentURL.query == "asset=seg", "URI queries changed")
        try require(text.contains("URI=\"https://example.invalid/key\""), "Foreign origin was redirected or given credentials")
        let (initialization, initResponse) = try await fetch(initURL)
        let (segment, segmentResponse) = try await fetch(segmentURL)
        try require(initResponse.statusCode == 200 && initialization == Data("synthetic-init".utf8), "MAP authentication or bytes changed")
        try require(segmentResponse.statusCode == 200 && segment == bytes, "Segment authentication or bytes changed")

        // 接続先が変わる前のクライアントを取り消しても、新しい中継要求は正常に使えること。
        let live = try await mapped(base.appendingPathComponent("api/streams/live/contract/720p/mpegts"))
        let received = try await withCheckedThrowingContinuation { continuation in
            let delegate = CancelAfterData(continuation)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            session.dataTask(with: live).resume()
        }
        try require(received > 0, "Live stream did not deliver initial bytes")
        let (afterCancel, afterResponse) = try await fetch(resource)
        try require(afterResponse.statusCode == 200 && afterCancel == bytes, "Cancelled old request broke next request")
        var closed = false
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let (metrics, _) = try await fetch(base.appendingPathComponent("metrics"))
            let values = try JSONSerialization.jsonObject(with: metrics) as? [String: Int]
            if values?["active_streams"] == 0 && (values?["cancelled_streams"] ?? 0) >= 1 {
                closed = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try require(closed, "Cancelled downstream left upstream stream alive")
    }
}
