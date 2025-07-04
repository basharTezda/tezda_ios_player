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
    private var nextVideoUrl: URL!
    private var nextVideoPlayerItems: [CachingPlayerItem] = []
    private var appStateObservers = [NSObjectProtocol]()
    private var isInAppSwitcher = false
    private var progressSlider: UISlider!
    private var isSliding = false
    private var bufferProgressView: UIProgressView!
    private var isUserSliding = false
    private var isProgrammaticUpdate = false

    init(frame: CGRect, videoURL: URL, isMuted: Bool, isLandScape: Bool, nextVideos: [String]) {
        url = videoURL
        super.init(frame: frame)
        backgroundColor = .black
        if let url = URL(string: videoURL.absoluteString) {
            // Valid URL
            print("Valid URL: \(url)")
        } else {
            // Invalid URL
            print("Invalid URL")
        }

        let playerItem: AVPlayerItem
        if let cachedAsset = self.asset(for: videoURL) {
            playerItem = AVPlayerItem(asset: cachedAsset)
            initPlayer(playerItem: playerItem, isMuted: isMuted, isLandScape: isLandScape)
        } else {
            // if !isConnectedToNetwork() {
            //     let eventData: [String: Any] = [
            //         "message": "No network connection and no cached video found."

            //     ]
            //     NotificationCenter.default.post(
            //         name: Notification.Name("VideoDurationUpdate"),
            //         object: "No network connection and no cached video found.")
            //     playerItem = AVPlayerItem(url: URL(string: videoURL.absoluteString)!)
            //     initPlayer(playerItem: playerItem, isMuted: isMuted, isLandScape: isLandScape)
            //     return
            // }

            if player == nil {
                playerItem = CachingPlayerItem(url: videoURL)
                (playerItem as? CachingPlayerItem)?.delegate = self
                initPlayer(playerItem: playerItem, isMuted: isMuted, isLandScape: isLandScape)
            }
        }
        setupAppStateObservers()
        setupAppSwitcherObservers()
        setupProgressSlider()
        setupGestureRecognizers()

        self.cacheVideoUrls(urls: nextVideos) { FlutterResult in
            // let eventData: [String: Any] = [
            //     "message": "Result \(FlutterResult)"

            // ]
            // NotificationCenter.default.post(
            //     name: Notification.Name("VideoDurationUpdate"), object: eventData)
        }

    }
    private func setupProgressSlider() {
        progressSlider = UISlider()
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.value = 0
        progressSlider.minimumTrackTintColor = .red
        progressSlider.maximumTrackTintColor = .clear
        progressSlider.thumbTintColor = .white
        
        // Make thumb visible and interactive
//        progressSlider.setThumbImage(UIImage(systemName: "circle.fill"), for: .normal)
//        progressSlider.setThumbImage(UIImage(systemName: "circle.fill"), for: .highlighted)
//        
        // Add targets
        progressSlider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(sliderTouchDown(_:)), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderTouchUp(_:)), for: [.touchUpInside, .touchUpOutside])
        
        addSubview(progressSlider)
        
        // Constraints
        NSLayoutConstraint.activate([
            progressSlider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            progressSlider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            progressSlider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            progressSlider.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // Buffer progress view
        bufferProgressView = UIProgressView()
        bufferProgressView.translatesAutoresizingMaskIntoConstraints = false
        bufferProgressView.progressTintColor = UIColor.lightGray.withAlphaComponent(0.3)
        bufferProgressView.trackTintColor = .clear
        insertSubview(bufferProgressView, belowSubview: progressSlider)
        
        NSLayoutConstraint.activate([
            bufferProgressView.leadingAnchor.constraint(equalTo: progressSlider.leadingAnchor),
            bufferProgressView.trailingAnchor.constraint(equalTo: progressSlider.trailingAnchor),
            bufferProgressView.centerYAnchor.constraint(equalTo: progressSlider.centerYAnchor),
            bufferProgressView.heightAnchor.constraint(equalToConstant: 2)
        ])
    }
    @objc private func sliderTouchDown(_ sender: UISlider) {
        isUserSliding = true
        player.pause()
    }

    @objc private func sliderValueChanged(_ sender: UISlider) {
        guard !isProgrammaticUpdate else { return }
        
        if isUserSliding {
            // Example: Apply some transformation to the value
            let transformedValue = transformSliderValue(sender.value)
            
            if transformedValue != sender.value {
                isProgrammaticUpdate = true
                sender.value = transformedValue
                isProgrammaticUpdate = false
            }
            
            // Update some visual indicator
            updateTimeLabel(for: sender.value)
        }
    }

    @objc private func sliderTouchUp(_ sender: UISlider) {
        isUserSliding = false
        seekToCurrentSliderPosition(sender)
    }

    private func transformSliderValue(_ value: Float) -> Float {
        // Example: Apply logarithmic scaling
        return log10f(value * 9 + 1) // Maps 0...1 to 0...1 with log curve
    }

    private func updateTimeLabel(for value: Float) {
        guard let duration = player.currentItem?.duration.seconds,
              duration.isFinite, duration > 0 else { return }
        
        let time = Double(value) * duration
//        timeLabel.text = formatTime(time)
    }

    private func seekToCurrentSliderPosition(_ sender: UISlider) {
        guard let duration = player.currentItem?.duration.seconds,
              duration.isFinite, duration > 0 else { return }
        
        let targetTime = Double(sender.value) * duration 
        let seekTime = CMTime(seconds: targetTime, preferredTimescale: 1000)
        
        player.seek(to: seekTime) { [weak self] _ in
            self?.player.play()
        }
    }

    private func setupGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        addGestureRecognizer(tapGesture)
        
        // Make sure user interaction is enabled
        isUserInteractionEnabled = true
    }
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        if player.timeControlStatus == .playing {
            pause()
        } else {
            play()
        }
        
  
    }

    private func setupAppStateObservers() {
        // Observe app going to background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pause()
            let eventData: [String: Any] = [
                "message": " app in background"

            ]
            NotificationCenter.default.post(
                name: Notification.Name("VideoDurationUpdate"), object: eventData)
        }

        // Observe app coming to foreground
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let eventData: [String: Any] = [
                "message": " app in foreground"

            ]
            NotificationCenter.default.post(
                name: Notification.Name("VideoDurationUpdate"), object: eventData)
            if self?.isViewVisible() == true {
                self?.play()
            }
        }

        appStateObservers.append(contentsOf: [backgroundObserver, foregroundObserver])
    }
    private func setupAppSwitcherObservers() {
        // Observe when app enters app switcher
        let willResignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInAppSwitcher = true
            self?.pause()
        }

        // Observe when app returns from app switcher
        let didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInAppSwitcher = false
            if self?.isViewVisible() == true {
                self?.play()
            }
        }

        appStateObservers.append(contentsOf: [willResignObserver, didBecomeActiveObserver])
    }
    private func isViewVisible() -> Bool {
        guard !isInAppSwitcher else { return false }
        guard let window = self.window else { return false }
        let viewFrame = self.convert(self.bounds, to: window)
        let screenFrame = window.bounds

        let intersection = screenFrame.intersection(viewFrame)
        let visibleArea = intersection.width * intersection.height
        let totalArea = bounds.width * bounds.height

        let visibilityRatio = visibleArea / max(totalArea, 1)
        return visibilityRatio >= 0.99
    }
    public func cacheVideoUrls(urls: [String], result: @escaping FlutterResult) {

        DispatchQueue.global(qos: .utility).async {

            let group = DispatchGroup()
            for urlString in urls {

                guard let urlo = URL(string: urlString) else {

                    continue

                }
                group.enter()

                self.cacheNextVideoIfNeeded(url: urlo) {
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                result(true)
            }
        }
    }
    private func cacheNextVideoIfNeeded(url: URL, completion: @escaping () -> Void) {
        // Check if we already have this video cached
        if self.asset(for: url) != nil {
            completion()
            return
        }

        // Only cache if we have network connection
        guard isConnectedToNetwork() else {
            completion()
            return
        }
        let eventData: [String: Any] = [
            "message": "trying to cache \(url.absoluteString)"

        ]
        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"), object: eventData)
        // Create and prepare the next video player item for caching
        let nextVideoPlayerItem = CachingPlayerItem(url: url)
        nextVideoPlayerItem.delegate = self

        // We don't actually need to play it, just prepare it for caching
        let tempPlayer = AVPlayer(playerItem: nextVideoPlayerItem)
        tempPlayer.automaticallyWaitsToMinimizeStalling = false
        tempPlayer.isMuted = true

        // Set rate to 0.1 to start loading but not actually play
        tempPlayer.rate = 0.1
        nextVideoPlayerItems.append(nextVideoPlayerItem)
        // After a short delay, pause it to prevent unnecessary bandwidth usage
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            tempPlayer.rate = 0
        }
        completion()
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
        let eventData: [String: Any] = [
            "isPlaying": true

        ]
        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"), object: eventData)
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
            self, selector: #selector(play),
            name: NSNotification.Name("play"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(pause),
            name: NSNotification.Name("pause"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(toggleMute),
            name: NSNotification.Name("ToggleMute"), object: nil)
    }
    private func addPeriodicTimeObserver() {
        removePeriodicTimeObserver()
        
        // Update interval to 1 millisecond (1/1000 of a second)
        let interval = CMTime(
            value: 1,          // 1 unit of the timescale
            timescale: 1000    // 1000 units per second = milliseconds
        )
        
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: DispatchQueue.main
        ) { [weak self] time in
            guard let self = self else { return }
            
            let currentTime = time.seconds
            let duration = self.player.currentItem?.duration.seconds ?? 0
            
            // Only update slider if user isn't interacting with it
            if !self.isSliding && duration > 0 {
                self.progressSlider.value = Float(currentTime / duration)
            }
            
//            self.sendVideoDuration(currentTime: currentTime, duration: duration)
        }
    }

//    @objc private func sendVideoDuration(currentTime: Double, duration: Double) {
//        if !isSliding && duration > 0 {
//            progressSlider.value = Float(currentTime / duration)
//        }
//        // Prepare the event data and send it to Flutter
//        let eventData: [String: Any] = [
//            "currentTime": currentTime,
//            "duration": duration,
//        ]
//        NotificationCenter.default.addObserver(
//            self, selector: #selector(handleSeekToNotification(_:)),
//            name: Notification.Name("SeekToTimeNotification"), object: nil)
//
//        NotificationCenter.default.post(
//            name: Notification.Name("VideoDurationUpdate"), object: eventData)
//    }
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
    @objc private func play() {
        DispatchQueue.main.async {
            if self.player.timeControlStatus == .paused {
                self.player.play()
                let eventData: [String: Any] = [
                    "isPlaying": true

                ]
                NotificationCenter.default.post(
                    name: Notification.Name("VideoDurationUpdate"), object: eventData)
            }
        }
    }
    @objc private func pause() {
        DispatchQueue.main.async {
            if self.player.timeControlStatus == .playing {
                self.player.pause()
                let eventData: [String: Any] = [
                    "isPlaying": false

                ]
                NotificationCenter.default.post(
                    name: Notification.Name("VideoDurationUpdate"), object: eventData)
            }
        }
    }
    @objc private func toggleMute() {
        player.isMuted = !player.isMuted
    }

    override func layoutSubviews() {

        super.layoutSubviews()
        playerLayer.frame = bounds
        bringSubviewToFront(progressSlider)

        if isInAppSwitcher {
            pause()
        } else {
            if isViewVisible() {
                play()
            } else {
                pause()
            }
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if isInAppSwitcher {
            pause()
        } else {
            if isViewVisible() {
                play()
            } else {
                pause()
            }
        }
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
                let duration = currentItem.duration.seconds
                if duration > 0 {
                    bufferProgressView.progress = Float(bufferedTime / duration)
                }
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

        appStateObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }

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

}

extension VideoPlayerUIView: CachingPlayerItemDelegate {

    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingData data: Data) {
        let isPlayerItemInNextItems = nextVideoPlayerItems.contains { $0 == playerItem }
        let urlToCache = isPlayerItemInNextItems ? playerItem.url : url
        self.save(data: data, for: urlToCache!)

        let eventData: [String: Any] = [
            "message": "Video downloaded successfully.",
            "isNextVideo": isPlayerItemInNextItems,
        ]
        NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"),
            object: eventData)
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
            "message": "no cached data found for this \(url.absoluteString)."

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
            "message": "no cached file found for this \(url.absoluteString)."

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
