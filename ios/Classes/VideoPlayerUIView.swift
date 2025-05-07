import AVFoundation
import UIKit

class VideoPlayerUIView: UIView {
    private var player: AVPlayer!
    private var playerLayer: AVPlayerLayer!
    private var isPlaying = false

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
        adjustVideoGravityForOrientation()
    }

    @objc private func loopVideo() {
        player.seek(to: .zero)
        player.play()
    }

    @objc private func togglePlayPause() {
        DispatchQueue.main.async {
            if self.player.timeControlStatus == .playing {
                self.player.pause()
                self.isPlaying = false

            } else {
                self.player.play()
                self.isPlaying = true

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
                checkVisibilityAndUpdatePlayPause() 
                // player.play()
            }
        // case "playbackBufferEmpty":
        //     SwiftNativeVideoPlayerPlugin.eventSink?(["buffering": true])
        // case "playbackLikelyToKeepUp":
        //     SwiftNativeVideoPlayerPlugin.eventSink?(["buffering": false])
        // case "presentationSize":
        //     let size = item.presentationSize
        //     let isLandscape = size.width > size.height
        //     playerLayer.videoGravity = isLandscape ? .resizeAspect : .resizeAspectFill
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

    private func adjustVideoGravityForOrientation() {
        guard let item = player.currentItem else { return }

        let size = item.presentationSize
        if size.height > size.width {
            // Portrait video
            playerLayer.videoGravity = .resizeAspectFill
        } else {
            // Landscape video
            playerLayer.videoGravity = .resizeAspect
        }
    }
    @objc private func handleTap() {
        // Toggle play/pause state on tap
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        // Toggle the state
        isPlaying.toggle()
    }
}

extension VideoPlayerUIView {
    func changeVideo(to url: URL) {
        player.pause()  // Pause current video

        // Remove current player layer
        playerLayer.removeFromSuperlayer()

        // Create a new player for the new URL
        player = AVPlayer(url: url)
        player.isMuted = false

        // Set up the new player layer
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        // Start playing the new video
        // player.play()
    }

    func play() {
        player.play()
    }
    func pause() {
        player.pause()
    }
    func mute() {
        player.isMuted = true
    }
    func unmute() {
        player.isMuted = false
    }
}
