import AVFoundation
import Cache
import Flutter
import SystemConfiguration
import UIKit

func isConnectedToNetwork() -> Bool {
    let reachability = SCNetworkReachabilityCreateWithName(nil, "www.apple.com")
    var flags = SCNetworkReachabilityFlags()

    if SCNetworkReachabilityGetFlags(reachability!, &flags) == false {
        return false
    }

    let isReachable = flags.contains(.reachable)
    let needsConnection = flags.contains(.connectionRequired)

    return isReachable && !needsConnection
}

let diskConfig = DiskConfig(name: "VideoCache")
let memoryConfig = MemoryConfig(expiry: .never, countLimit: 10, totalCostLimit: 10)
let storage = try? Storage<String, Data>(
    diskConfig: diskConfig, memoryConfig: memoryConfig, transformer: TransformerFactory.forData())

class VideoPlayerUIView: UIView {
    private var player: AVPlayer!
    private var playerLayer: AVPlayerLayer!
    private var timeObserverToken: Any?
    private var url: URL!

    init(frame: CGRect, videoURL: URL, isMuted: Bool, isLandScape: Bool, nextVideo: URL) {
        url = videoURL
        super.init(frame: frame)
        backgroundColor = .black
        if storage == nil {
            let eventData: [String: Any] = [
                "message": "Storage is nil"

            ]
            NotificationCenter.default.post(
                name: Notification.Name("VideoDurationUpdate"), object: eventData)

        } else {
            let eventData: [String: Any] = [
                "message": "Storage is not nil"

            ]
            NotificationCenter.default.post(
                name: Notification.Name("VideoDurationUpdate"), object: eventData)
        }
        let playerItem: AVPlayerItem
        if let cachedAsset = self.asset(for: videoURL) {
            playerItem = AVPlayerItem(asset: cachedAsset)
            initPlayer(playerItem: playerItem, isMuted: isMuted, isLandScape: isLandScape)
        } else {
            if !isConnectedToNetwork() {
                let eventData: [String: Any] = [
                    "message": "No network connection and no cached video found."

                ]
                NotificationCenter.default.post(
                    name: Notification.Name("VideoDurationUpdate"), object: eventData)
                playerItem = AVPlayerItem(url: URL(string: videoURL.absoluteString)!)
                initPlayer(playerItem: playerItem, isMuted: isMuted, isLandScape: isLandScape)
                return
            }

            playerItem = CachingPlayerItem(url: videoURL)
            (playerItem as? CachingPlayerItem)?.delegate = self
            initPlayer(playerItem: playerItem, isMuted: isMuted, isLandScape: isLandScape)
        }
        if let cachedAsset = self.asset(for: nextVideo) {
            let playerItem = AVPlayerItem(asset: cachedAsset)
        } else {
            if !isConnectedToNetwork() {
                let eventData: [String: Any] = [
                    "message": "No network connection and no cached video found."

                ]
                NotificationCenter.default.post(
                    name: Notification.Name("VideoDurationUpdate"), object: eventData)
                return
            }
            let playerItem = CachingPlayerItem(url: nextVideo)
            (playerItem as? CachingPlayerItem)?.delegate = self
        }

    }
    private func initPlayer(playerItem: AVPlayerItem, isMuted: Bool, isLandScape: Bool) {
        player = AVPlayer(playerItem: playerItem)
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = false
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        player.play()
        playerLayer.videoGravity = isLandScape ? .resizeAspect : .resizeAspectFill
        layer.addSublayer(playerLayer)

        if let item = player.currentItem {
            item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
            item.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
        }
        player.currentItem?.addObserver(
            self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)
        player.currentItem?.addObserver(
            self, forKeyPath: "playbackLikelyToKeepUp", options: [.new], context: nil)
        player.currentItem?.addObserver(
            self, forKeyPath: "presentationSize", options: [.new], context: nil)
        addPeriodicTimeObserver()

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
    private func addPeriodicTimeObserver() {
        // Add periodic time observer for updating video duration and current time
        let interval = CMTime(seconds: 1, preferredTimescale: 1)

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: DispatchQueue.main
        ) { [weak self] time in
            self?.sendVideoDuration(
                currentTime: time.seconds, duration: self?.player.currentItem?.duration.seconds ?? 0
            )
        }
    }

    @objc private func sendVideoDuration(currentTime: Double, duration: Double) {
        // Prepare the event data and send it to Flutter
        let eventData: [String: Any] = [
            "currentTime": currentTime,
            "duration": duration,
        ]
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSeekToNotification(_:)),
            name: Notification.Name("SeekToTimeNotification"), object: nil)

        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"), object: eventData)
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
                //                player.play()
                let eventData: [String: Any] = [
                    "started": true

                ]
                NotificationCenter.default.post(
                    name: Notification.Name("VideoDurationUpdate"), object: eventData)

            }
        case "loadedTimeRanges":
            if let currentItem = player.currentItem {
                let bufferedTime =
                    currentItem.loadedTimeRanges.first?.timeRangeValue.duration.seconds ?? 0
                let eventData: [String: Any] = [
                    "buffering": bufferedTime

                ]
                NotificationCenter.default.post(
                    name: Notification.Name("VideoDurationUpdate"), object: eventData)

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
        removePeriodicTimeObserver()
        NotificationCenter.default.removeObserver(
            self, name: Notification.Name("SeekToTimeNotification"), object: nil)

    }
    private func removePeriodicTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    @objc private func handleSeekToNotification(_ notification: Notification) {
        if let time = notification.object as? Double {
            // Perform seek operation on the AVPlayer
            let seekTime = CMTime(seconds: time, preferredTimescale: 600)
            player.seek(to: seekTime) { completed in
                if completed {
                    print("Seek to \(time) seconds successful.")
                } else {
                    print("Seek operation failed.")
                }
            }
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

extension VideoPlayerUIView: CachingPlayerItemDelegate {

    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingData data: Data) {
        self.save(data: data, for: self.url)
        let eventData: [String: Any] = [
            "message": "Video downloaded successfully."

        ]
        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"), object: eventData)
    }

    func playerItem(
        _ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int,
        outOf bytesExpected: Int
    ) {

    }

    func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem) {
        let eventData: [String: Any] = [
            "message":
                "Not enough data for playback. Probably because of the poor network. Wait a bit and try to play later."

        ]
        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"),
            object:
                eventData
        )

    }

    func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error) {
        let eventData: [String: Any] = [
            "error": error

        ]
        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"), object: eventData)

    }

}
extension VideoPlayerUIView {

    func cacheVideo(from url: URL) {
        // Attempt to load the video data
        guard let videoData = try? Data(contentsOf: url) else {
            let eventData: [String: Any] = [
                "message": "Failed to load video data from URL."

            ]
            NotificationCenter.default.post(
                name: Notification.Name("VideoDurationUpdate"), object: eventData)
            return
        }

        // Save the video data to disk cache
        let cacheURL = getCacheURL(for: url)
        do {
            try storage?.setObject(videoData, forKey: url.absoluteString)
            if let cachedData = try? storage?.object(forKey: url.absoluteString),
                cachedData == videoData
            {
                let eventData: [String: Any] = [
                    "message": "Video cached successfully."

                ]
                NotificationCenter.default.post(
                    name: Notification.Name("VideoDurationUpdate"), object: eventData)
            } else {
                let eventData: [String: Any] = [
                    "message": "Failed to cache video data."

                ]
                NotificationCenter.default.post(
                    name: Notification.Name("VideoDurationUpdate"), object: eventData)
            }

        } catch {

            let eventData: [String: Any] = [
                "message": "Error caching video: \(error)"

            ]
            NotificationCenter.default.post(
                name: Notification.Name("VideoDurationUpdate"), object: eventData)

        }
    }

    func getVideo(from url: URL) -> Data? {
        if let cachedData = try? storage?.object(forKey: url.absoluteString) {
            return cachedData
        }
        let eventData: [String: Any] = [
            "message": "no cached data found for this URL."

        ]
        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"), object: eventData)
        return nil
    }

    func removeVideo(from url: URL) {
        try? storage?.removeObject(forKey: url.absoluteString)
    }

    func clearCache() {
        try? storage?.removeAll()
    }

    func asset(for url: URL) -> AVAsset? {
        if let data = getVideo(from: url) {
            let cacheURL = getCacheURL(for: url)
            try? data.write(to: cacheURL)
            return AVURLAsset(url: cacheURL)
        }
        let eventData: [String: Any] = [
            "message": "no cached file found for this URL."

        ]
        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"), object: eventData)
        return nil
    }

    func save(data: Data, for url: URL) {
        cacheVideo(from: url)
    }

    private func getCacheURL(for url: URL) -> URL {
        // Define the cache directory and the file name based on the URL's absolute string
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
        let cacheURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)

        return cacheURL
    }
}
