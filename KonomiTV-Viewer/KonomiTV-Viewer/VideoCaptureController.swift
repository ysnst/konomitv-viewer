@preconcurrency import AVFoundation
import CoreImage
@preconcurrency import Photos
import UIKit
@preconcurrency import VLCKit

private enum VideoCaptureFailure: Error { case frameUnavailable, photosDenied }
private struct EncodedCapture: Sendable { let fileName: String; let jpeg: Data }

/// 映像フレームと字幕・文字スーパーだけを合成する。実況や操作 UI はキャプチャしない。
/// VLC snapshot に PTS はないため、字幕は取得要求時点の近似である。
@MainActor
final class VideoCaptureController {
    private var captureTask: Task<Void, Never>?
    private var generation = 0
    // 保存開始後はPhotosのトランザクションを取り消せない。完了まで次の撮影を受け付けない。
    private var isSaving = false
    private(set) var isCapturing = false
    var onStateChanged: (() -> Void)?
    var onError: ((String) -> Void)?
    var onResult: ((String) -> Void)?

    func cancel() {
        guard !isSaving else { return }
        generation += 1
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        onStateChanged?()
    }

    func capture(vlcPlayer: VLCMediaPlayer?, playerItem: AVPlayerItem?, caption: UIImage?, superimpose: UIImage?,
                 metadata: CaptureMetadata, capturedAt: Date, presenter: UIViewController, isCurrent: @escaping () -> Bool) {
        guard !isCapturing, isCurrent(), presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil else { return }
        guard vlcPlayer != nil || playerItem != nil else {
            onError?("映像を取得できる再生状態ではありません。")
            return
        }
        generation += 1
        let token = generation
        let settings = SyncedSettingsStore.shared.current
        let captionMode = settings.captureCaptionMode
        let destinationContext = WatchedHistoryStore.Context.current
        isCapturing = true
        onStateChanged?()
        captureTask = Task { [weak self, weak presenter] in
            guard let self else { return }
            var output: AVPlayerItemVideoOutput?
            var temporaryDirectory: URL?
            defer {
                if let output { playerItem?.remove(output) }
                if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
                // cancel→次の要求の順で進んでも、古い処理が新しい状態を消さない。
                if self.generation == token {
                    self.isSaving = false
                    self.captureTask = nil
                    self.isCapturing = false
                    self.onStateChanged?()
                }
            }
            do {
                try Task.checkCancellation()
                guard self.generation == token, isCurrent() else { return }
                let frame: UIImage
                if let vlcPlayer {
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("KonomiTV-Capture-\(UUID().uuidString)", isDirectory: true)
                    temporaryDirectory = directory
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let file = directory.appendingPathComponent("frame.png")
                    // Objective-C の境界で NSException を捕捉する。失敗で通常再生を停止しない。
                    guard NativeVideoSnapshot.save(player: vlcPlayer, path: file.path) else {
                        throw VideoCaptureFailure.frameUnavailable
                    }
                    var captured: UIImage?
                    for _ in 0..<40 {
                        try Task.checkCancellation()
                        guard self.generation == token, isCurrent() else { return }
                        captured = await Task.detached(priority: .userInitiated) {
                            autoreleasepool { UIImage(contentsOfFile: file.path) }
                        }.value
                        if captured != nil { break }
                        try await Task.sleep(nanoseconds: 50_000_000)
                    }
                    guard let captured else { throw VideoCaptureFailure.frameUnavailable }
                    frame = captured
                } else if let playerItem {
                    let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
                    // 取得のために通常のハードウェア描画を止めない。出力は要求中だけ追加する。
                    videoOutput.suppressesPlayerRendering = false
                    output = videoOutput
                    playerItem.add(videoOutput)
                    var captured: UIImage?
                    for _ in 0..<40 {
                        try Task.checkCancellation()
                        guard self.generation == token, isCurrent() else { return }
                        let time = playerItem.currentTime()
                        captured = await Task.detached(priority: .userInitiated) {
                            autoreleasepool { () -> UIImage? in
                                guard let buffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return nil }
                                let source = CIImage(cvPixelBuffer: buffer)
                                let context = CIContext(options: [.cacheIntermediates: false])
                                guard let image = context.createCGImage(source, from: source.extent) else { return nil }
                                return UIImage(cgImage: image)
                            }
                        }.value
                        if captured != nil { break }
                        try await Task.sleep(nanoseconds: 50_000_000)
                    }
                    guard let captured else { throw VideoCaptureFailure.frameUnavailable }
                    frame = captured
                } else { throw VideoCaptureFailure.frameUnavailable }

                // フレーム取得後にAV出力を残す理由はない。アップロード待ちの間の余分な出力を止める。
                if let activeOutput = output {
                    playerItem?.remove(activeOutput)
                    output = nil
                }
                try Task.checkCancellation()
                guard self.generation == token, isCurrent() else { return }
                let software = "KonomiTV Viewer version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")"
                let captures = try await Task.detached(priority: .userInitiated) {
                    try autoreleasepool { () -> [EncodedCapture] in
                        let images = Self.compose(frame: frame, caption: caption, superimpose: superimpose, captionMode: captionMode)
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        formatter.dateFormat = "yyyyMMdd-HHmmss"
                        let baseName = "Capture_" + formatter.string(from: capturedAt)
                        return try images.map { image, hasCaption in
                            guard let jpeg = image.jpegData(compressionQuality: 0.99) else { throw VideoCaptureFailure.frameUnavailable }
                            var information = metadata
                            information.is_caption_composited = hasCaption
                            return EncodedCapture(fileName: baseName + (hasCaption ? "_caption" : "") + ".jpg",
                                jpeg: try CaptureJPEG.encode(jpeg, metadata: information, capturedAt: capturedAt, software: software))
                        }
                    }
                }.value
                try Task.checkCancellation()
                guard self.generation == token, isCurrent(), let presenter,
                      presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed,
                      presenter.presentedViewController == nil else { return }
                guard !captures.isEmpty else { throw VideoCaptureFailure.frameUnavailable }
                // 元フレームはJPEGへ変換済み。一時画像をアップロード完了まで残さない。
                if let directory = temporaryDirectory {
                    try? FileManager.default.removeItem(at: directory)
                    temporaryDirectory = nil
                }
                self.isSaving = true
                // サーバーと写真は独立した保存先。一方の失敗を他方への無断フォールバックにしない。
                // サーバーのみでは写真API自体を呼ばないため、写真権限も要求しない。
                var results: [String] = []
                if settings.captureSaveMode != .browser {
                    var uploaded = 0
                    var reason = ""
                    for capture in captures {
                        do {
                            guard destinationContext == WatchedHistoryStore.Context.current else { throw APIError.staleSession }
                            try await APIClient.shared.uploadCapture(jpeg: capture.jpeg, fileName: capture.fileName)
                            uploaded += 1
                        } catch APIError.badStatus(let status) {
                            reason = " (HTTP \(status))"
                        } catch {
                            reason = " (接続先・認証設定と通信状態を確認してください)"
                        }
                    }
                    results.append("サーバー: \(uploaded)/\(captures.count)枚保存" + (uploaded < captures.count ? "・失敗あり\(reason)" : ""))
                }
                if settings.captureSaveMode != .uploadServer {
                    do {
                        try await Self.saveToPhotos(captures)
                        results.append("写真ライブラリ: \(captures.count)枚保存")
                    } catch {
                        results.append("写真ライブラリ: 保存失敗。写真の追加権限と空き容量を確認してください。")
                    }
                }
                // 保存済みの事実を、途中のシークなどを理由に取消扱いしない。
                self.onResult?(results.joined(separator: "\n"))

            } catch CaptureJPEG.Failure.metadataTooLarge {
                guard self.generation == token, isCurrent() else { return }
                self.onError?("番組情報がJPEGのメタデータ上限を超えたため、保存できませんでした。")
            } catch is CancellationError {
                // 画面・画質・シークの変更による取り消しを通信失敗として表示しない。
            } catch {
                guard self.generation == token, isCurrent() else { return }
                self.onError?("映像をキャプチャできませんでした。映像の表示後にもう一度お試しください。")
            }
        }
    }

    private nonisolated static func saveToPhotos(_ captures: [EncodedCapture]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw VideoCaptureFailure.photosDenied }
        try await PHPhotoLibrary.shared().performChanges {
            for capture in captures {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = capture.fileName
                request.addResource(with: .photo, data: capture.jpeg, options: options)
            }
        }
    }

    private nonisolated static func compose(frame: UIImage, caption: UIImage?, superimpose: UIImage?, captionMode: CaptureCaptionMode) -> [(UIImage, Bool)] {
        guard let pixels = frame.cgImage, pixels.width > 0, pixels.height > 0 else { return [] }
        let size = CGSize(width: pixels.width, height: pixels.height)
        let destination = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let visibleCaption = caption.flatMap { image in
            image.size.width.isFinite && image.size.height.isFinite && image.size.width > 0 && image.size.height > 0 ? image : nil
        }
        func image(includeCaption: Bool) -> UIImage {
            renderer.image { _ in
                UIImage(cgImage: pixels).draw(in: destination)
                // PWAと同じく文字スーパーはどの字幕モードでも合成し、その後に字幕を重ねる。
                if let superimpose, superimpose.size.width > 0, superimpose.size.height > 0 {
                    superimpose.draw(in: AVMakeRect(aspectRatio: superimpose.size, insideRect: destination))
                }
                if includeCaption, let visibleCaption {
                    visibleCaption.draw(in: AVMakeRect(aspectRatio: visibleCaption.size, insideRect: destination))
                }
            }
        }
        return captionMode.captionVariants(hasCaption: visibleCaption != nil).map {
            (image(includeCaption: $0), $0)
        }
    }
}
