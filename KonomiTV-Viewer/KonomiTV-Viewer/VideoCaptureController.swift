@preconcurrency import AVFoundation
import CoreImage
import UIKit
@preconcurrency import VLCKit

/// 映像フレームと字幕・実況だけを合成する。画面全体や操作 UI はキャプチャしない。
/// VLC snapshot に PTS はないため、字幕・実況は取得要求時点の近似である。
@MainActor
final class VideoCaptureController {
    private var captureTask: Task<Void, Never>?
    private var generation = 0
    private(set) var isCapturing = false
    var onStateChanged: (() -> Void)?
    var onError: ((String) -> Void)?

    func cancel() {
        generation += 1
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        onStateChanged?()
    }

    func capture(vlcPlayer: VLCMediaPlayer?, playerItem: AVPlayerItem?, caption: UIImage?,
                 comments: UIView?, presenter: UIViewController, isCurrent: @escaping () -> Bool) {
        guard !isCapturing, isCurrent(), presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil else { return }
        guard vlcPlayer != nil || playerItem != nil else {
            onError?("映像を取得できる再生状態ではありません。")
            return
        }
        generation += 1
        let token = generation
        // 文字の現在位置だけを控える。元解像度への合成や画像変換は下の非同期処理へ渡す。
        let commentImage = comments.flatMap { view -> UIImage? in
            guard !view.isHidden, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
                view.layer.render(in: context.cgContext)
            }
        }
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
                        throw CaptureFailure.frameUnavailable
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
                    guard let captured else { throw CaptureFailure.frameUnavailable }
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
                    guard let captured else { throw CaptureFailure.frameUnavailable }
                    frame = captured
                } else { throw CaptureFailure.frameUnavailable }

                try Task.checkCancellation()
                guard self.generation == token, isCurrent() else { return }
                let images = await Task.detached(priority: .userInitiated) {
                    autoreleasepool { Self.compose(frame: frame, caption: caption, comments: commentImage) }
                }.value
                try Task.checkCancellation()
                guard self.generation == token, isCurrent(), let presenter,
                      presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed,
                      presenter.presentedViewController == nil else { return }
                guard !images.isEmpty else { throw CaptureFailure.frameUnavailable }
                // UIImage を渡し、標準の共有と「画像を保存」を使う。写真権限は OS/ホストが管理する。
                let activity = UIActivityViewController(activityItems: images, applicationActivities: nil)
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                    popover.permittedArrowDirections = []
                }
                presenter.present(activity, animated: true)
            } catch is CancellationError {
                // 画面・画質・シークの変更による取り消しを通信失敗として表示しない。
            } catch {
                guard self.generation == token, isCurrent() else { return }
                self.onError?("映像をキャプチャできませんでした。映像の表示後にもう一度お試しください。")
            }
        }
    }

    private enum CaptureFailure: Error { case frameUnavailable }

    private nonisolated static func compose(frame: UIImage, caption: UIImage?, comments: UIImage?) -> [UIImage] {
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
        // コメント面には余白も含まれる。映像の aspect-fit 領域だけを元フレームへ写す。
        let commentPixels: CGImage? = comments.flatMap { image in
            guard let cg = image.cgImage, image.size.width > 0, image.size.height > 0 else { return nil }
            let bounds = CGRect(origin: .zero, size: image.size)
            let videoRect = AVMakeRect(aspectRatio: size, insideRect: bounds)
            let crop = CGRect(x: videoRect.minX * image.scale, y: videoRect.minY * image.scale,
                              width: videoRect.width * image.scale, height: videoRect.height * image.scale)
            return cg.cropping(to: crop)
        }
        func image(includeCaption: Bool) -> UIImage {
            renderer.image { _ in
                UIImage(cgImage: pixels).draw(in: destination)
                if includeCaption, let visibleCaption {
                    visibleCaption.draw(in: AVMakeRect(aspectRatio: visibleCaption.size, insideRect: destination))
                }
                if let commentPixels { UIImage(cgImage: commentPixels).draw(in: destination) }
            }
        }
        let withoutCaption = image(includeCaption: false)
        // 本家の既定 Both と同様、表示中の字幕がある場合だけ字幕なし/ありの二枚を共有する。
        if visibleCaption != nil { return [withoutCaption, image(includeCaption: true)] }
        return [withoutCaption]
    }
}
