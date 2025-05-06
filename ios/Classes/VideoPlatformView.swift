import AVFoundation
import Flutter
import UIKit

class VideoPlatformView: NSObject, FlutterPlatformView {
    private let playerView: VideoPlayerUIView

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) {
        let url: URL
        if let dict = args as? [String: Any],
            let urlStr = dict["url"] as? String,
            let parsed = URL(string: urlStr)
        {
            url = parsed
        } else {
            url = URL(
                string:
                    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"
            )!
        }

        playerView = VideoPlayerUIView(frame: frame, videoURL: url)
        super.init()
    }

    func view() -> UIView {
        return playerView
    }
}

class VideoPlayerUIView: UIView {
    private var player: AVPlayer!
    private var playerLayer: AVPlayerLayer!

    init(frame: CGRect, videoURL: URL) {
        super.init(frame: frame)
        backgroundColor = .black

        player = AVPlayer(url: videoURL)
        player.isMuted = false

        playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        // Autoplay
        if let item = player.currentItem {
            item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        }
        player.currentItem?.addObserver(
            self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)
        player.currentItem?.addObserver(
            self, forKeyPath: "playbackLikelyToKeepUp", options: [.new], context: nil)
        player.currentItem?.addObserver(
            self, forKeyPath: "presentationSize", options: [.new], context: nil)

        // Looping
        NotificationCenter.default.addObserver(
            self, selector: #selector(loopVideo),
            name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)

        // Listen for toggle
        NotificationCenter.default.addObserver(
            self, selector: #selector(togglePlayPause),
            name: NSNotification.Name("TogglePlayPause"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(toggleMute),
            name: NSNotification.Name("ToggleMute"), object: nil)

    }

    @objc private func loopVideo() {
        player.seek(to: .zero)
        player.play()
    }

    @objc private func togglePlayPause() {
        DispatchQueue.main.async {
            if self.player.timeControlStatus == .playing {
                self.player.pause()
            } else {
                self.player.play()
            }
        }
    }

    @objc private func toggleMute() {
        player.isMuted = !player.isMuted
    }

    override func layoutSubviews() {

        super.layoutSubviews()
        playerLayer.frame = bounds
        checkVisibilityAndUpdatePlayPause()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        checkVisibilityAndUpdatePlayPause()
    }
    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        guard let item = object as? AVPlayerItem else { return }

        switch keyPath {
        case "status":
            if item.status == .readyToPlay {
                player.play()
            }
        // case "playbackBufferEmpty":
        //     SwiftNativeVideoPlayerPlugin.eventSink?(["buffering": true])
        // case "playbackLikelyToKeepUp":
        //     SwiftNativeVideoPlayerPlugin.eventSink?(["buffering": false])
        case "presentationSize":
            let size = item.presentationSize
            let isLandscape = size.width > size.height
            playerLayer.videoGravity = isLandscape ? .resizeAspect : .resizeAspectFill
        default:
            break
        }
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let item = player.currentItem {
            item.removeObserver(self, forKeyPath: "status")
        }
    }

    private func checkVisibilityAndUpdatePlayPause() {
        guard let window = self.window else { return }
        let viewFrame = self.convert(self.bounds, to: window)
        let screenFrame = window.bounds

        let intersection = screenFrame.intersection(viewFrame)
        let visibleArea = intersection.width * intersection.height
        let totalArea = bounds.width * bounds.height

        let visibilityRatio = visibleArea / max(totalArea, 1)

        // If less than 100% visible → pause, else play
        if visibilityRatio < 0.99 {
            player.pause()
        } else {
            player.play()
        }
    }
}
