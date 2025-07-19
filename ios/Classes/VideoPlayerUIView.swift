import AVFoundation
import Cache
import Flutter
import SystemConfiguration
import UIKit
private var activePlayers:   [String: AVPlayer]       = [:]   // LRU ≤ 4
private var preloadPlayers:  [String: AVPlayer]       = [:]   // tmp only
private var loadingItems:    [String: CachingPlayerItem] = [:]
private var upcomingQueue = [URL]()
private let maxPrefetch = 10 // ← up to 10 videos in your queue
/// A serial queue for prefetching, one at a time:
private let prefetchQueue: OperationQueue = {
  let q = OperationQueue()
  q.maxConcurrentOperationCount = 1
  return q
}()

/// Never have more than 10 dummy players in RAM at once:
private let maxConcurrentPrefetches = 10

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

// MARK: – Dual Disk Caches

// 1️⃣ permanent bucket: never expires, 2GB storage size
let permDiskConfig = DiskConfig(
  name: "VideoCachePerm",
  expiry: .never,
  maxSize: UInt(2048 * 1024 * 1024)
)
let permStorage = try? Storage<String, Data>(
  diskConfig: permDiskConfig,
  memoryConfig: MemoryConfig(),
  transformer: TransformerFactory.forData()
)

// 2️⃣ temporary bucket: 1 hr TTL, 500 MB cap
let tempDiskConfig = DiskConfig(
  name: "VideoCacheTemp",
  expiry: .seconds(3600),
  maxSize: UInt(500 * 1024 * 1024)
)
let tempStorage = try? Storage<String, Data>(
  diskConfig: tempDiskConfig,
  memoryConfig: MemoryConfig(),
  transformer: TransformerFactory.forData()
)
/// Track when each URL’s prefetch began, so we can evict if it hangs >30 min.
private var prefetchStartDates: [String: Date] = [:]

class VideoPlayerUIView: UIView {
    
    
    static let shared = VideoPlayerUIView(frame: .zero, videoURL: URL(string: "https://www.apple.com")!, isMuted: false, isLandScape: false, nextVideos: [])
    
    private var player: AVPlayer!
    private var playerLayer: AVPlayerLayer!
    private var timeObserverToken: Any?
    private var url: URL!
    private(set) var currentURL: URL!
    private var nextVideoUrl: URL!
    private var nextVideoPlayerItems: [CachingPlayerItem] = []
    private var appStateObservers = [NSObjectProtocol]()
    private var isInAppSwitcher = false
    private var progressSlider: UISlider!
    private var isSliding = false
    private var bufferProgressView: UIProgressView!
    private var isUserSliding = false
    private var isProgrammaticUpdate = false
    private var bufferingIndicator: UIActivityIndicatorView!
    private var preCachingList: [String] = []
    private var resumeWorkItem: DispatchWorkItem?
    private var neverShowBufferingIndicator = false
    private var currentTime: Double = 0.0
    private var duration: Double = 0.0
    private var playerItemContext = 0
    /// Move an unwatched clip from permStorage → tempStorage (starts its TTL)
    private func markWatched(_ url: URL) {
        let key = url.absoluteString
        // 1️⃣ pull bytes from permanent store
        guard let data = try? permStorage?.object(forKey: key) else { return }

        // 2️⃣ write into the TTL‐backed temp store
        try? tempStorage?.setObject(data, forKey: key)
        print("[Cache_Demonstration] Marked watched → moved to TTL bucket: \(key) (expires in 1h, cap 500 MB)")

        // 3️⃣ remove from permanent so it never lingers forever
        try? permStorage?.removeObject(forKey: key)
    }
    // at top of VideoPlayerUIView, with your other private vars
    private var hasSentDeinitEvent = false



    init(frame: CGRect, videoURL: URL, isMuted: Bool, isLandScape: Bool, nextVideos: [String]) {
        
        print("[Cache_Demonstration]: caching \(nextVideos.count) videos...")

        url = videoURL
        preCachingList = nextVideos
        super.init(frame: frame)
        let nextURLs = nextVideos.compactMap { URL(string: $0) }
        updateUpcomingQueue(with: nextURLs)
        backgroundColor = .black
        if let url = URL(string: videoURL.absoluteString) {
            // Valid URL
            print("Valid URL: \(url)")
        } else {
            // Invalid URL
            print("Invalid URL")
        }

        // 1️⃣ If it’s already playing on‑screen, reuse it:
        if let existing = activePlayers[videoURL.absoluteString] {
          initPlayer(player: existing, isMuted: isMuted, isLandScape: isLandScape)
        }

        // 2️⃣ Else if it’s sitting in preloadPlayers, promote that entire AVPlayer:
        else if let promoted = promotePreloaded(url: videoURL) {
          initPlayer(player: promoted, isMuted: isMuted, isLandScape: isLandScape)
        }

        // 3️⃣ Otherwise fall back to disk → network:
        else {
          let item: AVPlayerItem
          if let asset = localAsset(for: videoURL) {
            item = AVPlayerItem(asset: asset)
          } else {
            item = AVPlayerItem(url: videoURL)
          }
          initPlayer(playerItem: item, isMuted: isMuted, isLandScape: isLandScape)
        }

        
        // fire‐and‐forget background caching of this URL:
        cacheInBackground(url: videoURL)
        
        setupAppStateObservers()
        setupAppSwitcherObservers()
        setupProgressSlider()
        setupBufferingIndicator()
        setupGestureRecognizers()
        }
    /// Returns an AVPlayerItem by checking disk → RAM → network
    private func makePlayerItem(for url: URL) -> AVPlayerItem {
        let key = url.absoluteString

        // 1️⃣ watched? (TTL cache)
        if let data = try? tempStorage?.object(forKey: key) {
            let cacheURL = getCacheURL(for: url)
            try? data.write(to: cacheURL)
            return AVPlayerItem(asset: AVURLAsset(url: cacheURL))
        }

        // 2️⃣ unwatched but prefetched? (permanent cache)
        if let data = try? permStorage?.object(forKey: key) {
            let cacheURL = getCacheURL(for: url)
            try? data.write(to: cacheURL)
            return AVPlayerItem(asset: AVURLAsset(url: cacheURL))
        }

        // 3️⃣ fallback to network
        return AVPlayerItem(url: url)
    }

    /// Keeps exactly `maxPrefetch` URLs in RAM, prefetching them.
    private func updateUpcomingQueue(with nextVideos: [URL]) {
        // 1️⃣ update our FIFO list
        upcomingQueue = Array(nextVideos.prefix(maxPrefetch))

        // 2️⃣ prefetch any that aren’t already on disk or loading
        for url in upcomingQueue {
            prefetch(url: url)
        }
    }

    /// Starts a background download & RAM‑cache of one video
    private func prefetch(url: URL) {
        let key = url.absoluteString

        // 1️⃣ Already on disk or loading?
        guard loadingItems[key] == nil, asset(for: url) == nil else { return }

        // 2️⃣ Too many in‑flight?
        guard preloadPlayers.count < maxConcurrentPrefetches else {
            print("[Cache_Demonstration] 🔥 at limit (\(preloadPlayers.count))/\(maxConcurrentPrefetches), skipping \(key)")
            return
        }

        // Schedule _serially_ on our queue:
        let op = BlockOperation { [weak self] in
            guard let self = self else { return }
            print("[Cache_Demonstration] ▶️ start prefetch: \(key)")

            // record start time in the global map
            prefetchStartDates[key] = Date()

            // set up a CachingPlayerItem and dummy AVPlayer
            let cacheItem = CachingPlayerItem(url: url)
            cacheItem.delegate = self
            loadingItems[key] = cacheItem

            let dummy = AVPlayer(playerItem: cacheItem)
            dummy.isMuted = true
            dummy.rate = 1.0
            preloadPlayers[key] = dummy

            // stop after a bit of data
            Thread.sleep(forTimeInterval: 0.3)
            dummy.rate = 0

            // if it hasn’t completed in 30 min, evict
            DispatchQueue.main.asyncAfter(deadline: .now() + 1800) {
                if let start = prefetchStartDates[key],
                   Date().timeIntervalSince(start) >= 1800,
                   loadingItems[key] != nil
                {
                    print("[Cache_Demonstration] ⏰ evict hung prefetch: \(key)")
                    preloadPlayers[key]?.pause()
                    preloadPlayers.removeValue(forKey: key)
                    loadingItems.removeValue(forKey: key)
                    prefetchStartDates.removeValue(forKey: key)
                }
            }
        }

        prefetchQueue.addOperation(op)
    }



    
    /// Moves a pre‑loaded dummy player (if any) from preload → active.
    private func promotePreloaded(url: URL) -> AVPlayer? {
        guard let p = preloadPlayers.removeValue(forKey: url.absoluteString)
        else { return nil }

        p.seek(to: .zero)                       // make sure we start at 0
        loadingItems.removeValue(forKey: url.absoluteString)
        activePlayers[url.absoluteString] = p
        return p
    }

    /// Keep only currentURL + the 3 most‑recently‑prefetched URLs in memory.
    private func purgeOffscreenPlayers(maxInRAM: Int = 4) {
        // if we’re already at or below the limit, nothing to do
        guard activePlayers.count > maxInRAM else { return }

        // Make an LRU list: oldest keys first
        let keysInLRUOrder = activePlayers.keys

        for key in keysInLRUOrder where activePlayers.count > maxInRAM {
            // Don’t purge what the user is currently watching
            if key == currentURL.absoluteString { continue }

            // Pause & drop from RAM; data is already in disk cache
            activePlayers[key]?.pause()
            activePlayers[key]?.replaceCurrentItem(with: nil)
            activePlayers.removeValue(forKey: key)
            loadingItems.removeValue(forKey: key)
        }
    }

    /// Start a CachingPlayerItem download purely to fill disk cache, without ever attaching it to the on‑screen player.
    private func cacheInBackground(url: URL) {
        // if already cached or already downloading, do nothing
        guard asset(for: url) == nil, loadingItems[url.absoluteString] == nil else { return }

        let cacheItem = CachingPlayerItem(url: url)
        cacheItem.delegate = self
        loadingItems[url.absoluteString] = cacheItem

        // create a “dummy” AVPlayer so loading begins
        let dummy = AVPlayer(playerItem: cacheItem)
        dummy.isMuted = true
        dummy.automaticallyWaitsToMinimizeStalling = false

        // kick off a tiny bit of buffering
        dummy.rate = 0.1

        // then pause after a couple seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            dummy.rate = 0
        }
    }

        private func cleanupPlayer() {
        // Remove time observer
        removePeriodicTimeObserver()
        
        // Remove player item observers
        // if let currentItem = player?.currentItem {
        //     currentItem.removeObserver(self, forKeyPath: "status")
        //     currentItem.removeObserver(self, forKeyPath: "loadedTimeRanges")
        //     currentItem.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        //     currentItem.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        //     currentItem.removeObserver(self, forKeyPath: "presentationSize")
        //     currentItem.removeObserver(self, forKeyPath: "isPlaybackBufferFull")
            
        //     NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
        // }
        
        // Remove player layer
//        playerLayer?.removeFromSuperlayer()
//        playerLayer = nil
//
//        // Pause and nil the player
//        player?.pause()
//        player?.replaceCurrentItem(with: nil)
//        player = nil
//
//        // Clean up next video items
//        nextVideoPlayerItems.forEach { item in
//            item.delegate = nil
//            item.cancelPendingSeeks()
//            item.asset.cancelLoading()
//        }

    }
    
private func setupBufferingIndicator() {
    if #available(iOS 13.0, *) {
        bufferingIndicator = UIActivityIndicatorView(style: .large)
    } else {
        // For iOS 12 and earlier, use .whiteLarge which has been available since iOS 2.0
        bufferingIndicator = UIActivityIndicatorView(style: .whiteLarge)
    }
    bufferingIndicator.color = .white
    bufferingIndicator.translatesAutoresizingMaskIntoConstraints = false
    bufferingIndicator.hidesWhenStopped = true
    addSubview(bufferingIndicator)
    
    NSLayoutConstraint.activate([
        bufferingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
        bufferingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
    ])
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
        progressSlider.isHidden=true
        
        
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
        bufferProgressView.isHidden = true
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
        
        _ = Double(value) * duration
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
        // Single tap for play/pause
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        addGestureRecognizer(tapGesture)
        
        // Double tap for mute/unmute
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)
        
        // Make sure single tap doesn't interfere with double tap
        tapGesture.require(toFail: doubleTapGesture)
        
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
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let eventData: [String: Any] = [
            "onDoubleTap": true

        ]
        self.sendEvent(eventData: eventData)
      
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
            self?.sendEvent(eventData: eventData)
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
            self?.sendEvent(eventData: eventData)
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
        var iterator = urls.makeIterator()
        func cacheNext() {
            guard let s = iterator.next(), let u = URL(string: s) else {
                DispatchQueue.main.async { result(true) } // all done
                return
            }
            cacheNextVideoIfNeeded(url: u) { cacheNext() }
        }
        cacheNext()
    }
    private func cacheNextVideoIfNeeded(url: URL,
                                        completion: @escaping () -> Void) {

        guard asset(for: url) == nil,
              loadingItems[url.absoluteString] == nil else { completion(); return }

        let item   = CachingPlayerItem(url: url)
        item.delegate = self
        loadingItems[url.absoluteString] = item        // track it

        let dummy  = AVPlayer(playerItem: item)
        dummy.isMuted = true
        dummy.rate = 1.0                               // fetch quickly
        preloadPlayers[url.absoluteString] = dummy     // <‑‑ lives here

        // stop after 5 s of data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dummy.rate = 0 }
        completion()
    }
    private func initPlayer(player: AVPlayer,
                            isMuted: Bool,
                            isLandScape: Bool) {
        self.player = player
        finishInit(isMuted: isMuted, isLandScape: isLandScape)
    }

    private func initPlayer(playerItem: AVPlayerItem,
                            isMuted: Bool,
                            isLandScape: Bool) {
        self.player = AVPlayer(playerItem: playerItem)
        finishInit(isMuted: isMuted, isLandScape: isLandScape)
    }
    private func finishInit(isMuted: Bool, isLandScape: Bool) {
        markWatched(self.url)
        
        // register as “currently on screen”
        activePlayers[url.absoluteString] = player
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = false
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        player.play()
        currentURL = url        // mark this URL as the one on‑screen
        purgeOffscreenPlayers() // make sure we keep only 4 items in RAM
        playerLayer.videoGravity = isLandScape ? .resizeAspect : .resizeAspectFill
        layer.addSublayer(playerLayer)
        let eventData: [String: Any] = [
            "isPlaying": true
            
        ]
        self.sendEvent(eventData: eventData)
        if let item = player.currentItem {
            item.addObserver(self, forKeyPath: "status", options: [.new], context: &playerItemContext)
            item.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: &playerItemContext)
        }
        player.currentItem?.addObserver(
            self, forKeyPath: "playbackBufferEmpty", options: [.new], context: &playerItemContext)
        player.currentItem?.addObserver(
            self, forKeyPath: "playbackLikelyToKeepUp", options: [.new], context: &playerItemContext)
        //        player.currentItem?.addObserver(
        //            self, forKeyPath: "presentationSize", options: [.new], context: nil)
        player.currentItem?.addObserver(
            self, forKeyPath: "isPlaybackBufferFull", options: [.new], context: &playerItemContext)
        
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
        trimActivePlayers()
    }
    
    private func trimActivePlayers(maxInRAM: Int = 4) {
        let protectedKey = currentURL.absoluteString
        var keys = activePlayers.keys.filter { $0 != protectedKey }
        
        while keys.count > maxInRAM - 1 {
            if let victim = keys.first {
                activePlayers[victim]?.pause()
                activePlayers[victim]?.replaceCurrentItem(with: nil)
                activePlayers.removeValue(forKey: victim)
                keys.removeFirst()
            }
        }
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
            
            currentTime = time.seconds
            duration = self.player.currentItem?.duration.seconds ?? 0
         
            // Only update slider if user isn't interacting with it
//            if !self.isSliding && duration > 0 {
//                self.progressSlider.value = Float(currentTime / duration)
//            }
            
            self.sendVideoDuration(currentTime: currentTime, duration: duration)
        }
    }

    @objc private func sendVideoDuration(currentTime: Double, duration: Double) {
        if !isSliding && duration > 0 {
            progressSlider.value = Float(currentTime / duration)
        }
        DispatchQueue.main.async {
     self.bufferingIndicator.stopAnimating()
        }
          
        // Prepare the event data and send it to Flutter
//        let eventData: [String: Any] = [
//            "currentTime": currentTime,
//            "duration": duration,
//        ]
//        NotificationCenter.default.addObserver(
//            self, selector: #selector(handleSeekToNotification(_:)),
//            name: Notification.Name("SeekToTimeNotification"), object: nil)
//
//        NotificationCenter.default.post(
//            name: Notification.Name("VideoDurationUpdate"), object:  nil, userInfo: eventData)
    }
    @objc private func loopVideo() {
        let eventData: [String: Any] = [
            "onFinished": true,
            "duration": self.player.currentItem?.duration.seconds ?? 0,
        ]
        sendEvent(eventData: eventData)
        player.seek(to: .zero)
        player.play()
    }
@objc private func sendEvent(eventData: [String: Any]  ){
    NotificationCenter.default.post(
            name: Notification.Name("VideoDurationUpdate"), object:  nil, userInfo: eventData)
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
                self.sendEvent(eventData: eventData)
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
                self.sendEvent(eventData: eventData)
            }
        }
    }
    @objc private func toggleMute() {
        player.isMuted = !player.isMuted
    }
@objc private func sendOnDeinit() {
    let eventData: [String: Any] = [
"onDeinit": true,
"duration": self.player.currentItem?.duration.seconds ?? 0,
"currentTime": self.currentTime,
"video": self.url.absoluteString,
]
//print("\(eventData)")
sendEvent(eventData: eventData)
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

        // if we're being removed from the window, send deinit exactly once
        if window == nil && !hasSentDeinitEvent {
            hasSentDeinitEvent = true
            sendOnDeinit()
        }

        // then your normal play/pause logic
        if isInAppSwitcher {
            pause()
        } else if isViewVisible() {
            play()
        } else {
            pause()
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
              sendEvent(eventData: eventData)

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
              sendEvent(eventData: eventData)

            }
         case "playbackBufferEmpty":
          if !neverShowBufferingIndicator && player.timeControlStatus != .playing {
               DispatchQueue.main.async {
            self.bufferingIndicator.startAnimating()
               }
                 }
         
       
          case "playbackLikelyToKeepUp":
    
            DispatchQueue.main.async {
               
                 
                 // Cancel any pending resume
                 self.resumeWorkItem?.cancel()
                 
                 // Create new work item
                 let workItem = DispatchWorkItem { [weak self] in
                     guard let self = self else { return }
                     if self.player.timeControlStatus != .playing && self.isViewVisible(){
                         self.bufferingIndicator.stopAnimating()
                         self.player.play()
                     }
                 }
                 
                 self.resumeWorkItem = workItem
                 DispatchQueue.main.asyncAfter(
                     deadline: .now() + 4.0,
                     execute: workItem
                 )
             }
          
        case "isPlaybackBufferFull":
            // Another opportunity to resume playback
            DispatchQueue.main.async {
                self.bufferingIndicator.stopAnimating()
                if self.player.timeControlStatus != .playing && self.isViewVisible(){
                    self.player.play()
                }
            }
        // case "presentationSize":
        //     let size = item.presentationSize
        //     let isLandscape = size.width > size.height
        //     playerLayer.videoGravity = isLandscape ? .resizeAspect : .resizeAspectFill
        default:
            break
        }

    }
    func checkIfVideoHasAudio(asset: AVAsset, completion: @escaping (Bool) -> Void) {
        let audioTracks = asset.tracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            completion(true)
            return
        }
        
        // For more thorough checking (some formats might have audio in a different way)
        asset.loadValuesAsynchronously(forKeys: ["availableMediaCharacteristicsWithMediaSelectionOptions"]) {
            var hasAudio = false
            let mediaCharacteristics = asset.availableMediaCharacteristicsWithMediaSelectionOptions
            hasAudio = mediaCharacteristics.contains(.audible)
            
            DispatchQueue.main.async {
                completion(hasAudio)
            }
        }
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    
    func clearOldCachedVideos(maxCount: Int = 3) {
        while activePlayers.count > maxCount {
            if let key = activePlayers.keys.first {
                activePlayers[key]?.pause()
                activePlayers[key]?.replaceCurrentItem(with: nil)
                activePlayers.removeValue(forKey: key)
                loadingItems.removeValue(forKey: key)
            }
        }
    }
    
    deinit {
        
        if let item = player?.currentItem {
    item.removeObserver(self, forKeyPath: "status", context: &playerItemContext)
    item.removeObserver(self, forKeyPath: "loadedTimeRanges", context: &playerItemContext)
    item.removeObserver(self, forKeyPath: "playbackBufferEmpty", context: &playerItemContext)
    item.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp", context: &playerItemContext)
    item.removeObserver(self, forKeyPath: "isPlaybackBufferFull", context: &playerItemContext)
}
        //‑‑ pause & drop *this* player only
            if let key = url?.absoluteString {
                activePlayers[key]?.pause()
                activePlayers[key]?.replaceCurrentItem(with: nil)
                activePlayers.removeValue(forKey: key)
                loadingItems .removeValue(forKey: key)
                preloadPlayers.removeValue(forKey: key)
            }
        //‑‑ remove observers that belong to this instance
        NotificationCenter.default.removeObserver(self)
        removePeriodicTimeObserver()

        NotificationCenter.default.removeObserver(
            self, name: Notification.Name("SeekToTimeNotification"), object: nil)

        appStateObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }

    }
    }

extension VideoPlayerUIView: CachingPlayerItemDelegate {

    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingData data: Data) {
      let key = playerItem.url.absoluteString

      // 1️⃣ persist into permStorage immediately:
      try? permStorage?.setObject(data, forKey: key)
      print("[Cache_Demonstration] ✅ persisted \(key) (\(data.count) bytes) → permanent")

      // 2️⃣ clean up RAM
      if key != currentURL.absoluteString {
        preloadPlayers[key]?.pause()
        preloadPlayers.removeValue(forKey: key)
        loadingItems.removeValue(forKey: key)
      }
      prefetchStartDates.removeValue(forKey: key)
    }

    func playerItem(
        _ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int,
        outOf bytesExpected: Int
    ) {
        
    }

    func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem) {
            DispatchQueue.main.async {
        self.bufferingIndicator.startAnimating()
    }
        let eventData: [String: Any] = [
            "message": "Not enough data for playback. Probably because of the poor network. Wait a bit and try to play later.",
            "isBuffering": true
        ]
        
        self.sendEvent(eventData: eventData)
        
        // Optionally, you can automatically resume playback when ready
        playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferFull), options: [.new], context: &playerItemContext)
    }

    func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error) {
        let eventData: [String: Any] = [
            "error": error

        ]
        self.sendEvent(eventData: eventData)
        print("\(eventData)")

    }

}
extension VideoPlayerUIView {

    /// Attempt to read from TTL‐backed first, then permanent
    func getVideo(from url: URL) -> Data? {
      let key = url.absoluteString

      // 1️⃣ TTL cache (only “watched” videos)
      if let data = try? tempStorage?.object(forKey: key) {
        return data
      }

      // 2️⃣ permanent cache (“unwatched” prefetched videos)
      if let data = try? permStorage?.object(forKey: key) {
        return data
      }

      return nil
    }


    /// Remove a specific URL from both caches
    func removeVideo(from url: URL) {
      let key = url.absoluteString
      try? tempStorage?.removeObject(forKey: key)
      try? permStorage?.removeObject(forKey: key)
    }

    /// Wipe *all* cached videos
    func clearCache() {
      try? tempStorage?.removeAll()
      try? permStorage?.removeAll()
    }

    /// Load an AVAsset from whichever cache has it, writing bytes to disk.
    func asset(for url: URL) -> AVAsset? {
      let key = url.absoluteString
      let cacheURL = getCacheURL(for: url)

      // try TTL‐backed data first
      if let data = try? tempStorage?.object(forKey: key) {
        try? data.write(to: cacheURL)
        return AVURLAsset(url: cacheURL)
      }

      // then permanent
      if let data = try? permStorage?.object(forKey: key) {
        try? data.write(to: cacheURL)
        return AVURLAsset(url: cacheURL)
      }

      return nil
    }

    /// “Local asset” means reading directly from *either* cache without triggering network
    private func localAsset(for url: URL) -> AVURLAsset? {
      let key = url.absoluteString
      let cacheURL = getCacheURL(for: url)

      if let data = try? tempStorage?.object(forKey: key) {
        try? data.write(to: cacheURL)
        return AVURLAsset(url: cacheURL)
      }
      if let data = try? permStorage?.object(forKey: key) {
        try? data.write(to: cacheURL)
        return AVURLAsset(url: cacheURL)
      }
      return nil
    }
 

    private func getCacheURL(for url: URL) -> URL {
        // Define the cache directory and the file name based on the URL's absolute string
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
        let cacheURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)

        return cacheURL
    }
}
