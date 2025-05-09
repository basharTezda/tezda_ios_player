import Flutter
import UIKit
import CachingPlayerItem
import AVFoundation



class VideoPlayerUIView: UIView {
    private var player: AVPlayer!
    private var playerLayer: AVPlayerLayer!
    private var timeObserverToken: Any?

    init(frame: CGRect, videoURL: URL, isMuted: Bool,isLandScape: Bool ) {
        super.init(frame: frame)
        backgroundColor = .black
        
        let playerItem = CachingPlayerItem(url: videoURL)
        
        // Initialize AVPlayer with the player item
        player = AVPlayer(playerItem: playerItem)
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = false
   

        // playerItem.download()


        // Set up player layer to display the video
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
         player.play()
//        player = AVPlayer(url: videoURL)
  
        
//        playerLayer = AVPlayerLayer(player: player)
//        playerLayer.frame = bounds
        playerLayer.videoGravity = isLandScape ? .resizeAspect : .resizeAspectFill
        layer.addSublayer(playerLayer)

        // Autoplay
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
        
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] time in
            self?.sendVideoDuration(currentTime: time.seconds, duration: self?.player.currentItem?.duration.seconds ?? 0)
        }
    }
    
    @objc private func sendVideoDuration(currentTime: Double, duration: Double) {
         // Prepare the event data and send it to Flutter
         let eventData: [String: Any] = [
             "currentTime": currentTime,
             "duration": duration
         ]
        NotificationCenter.default.addObserver(self, selector: #selector(handleSeekToNotification(_:)), name: Notification.Name("SeekToTimeNotification"), object: nil)

         NotificationCenter.default.post(name: Notification.Name("VideoDurationUpdate"), object: eventData)
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
                    "started": true,
                    
                ]
                NotificationCenter.default.post(name: Notification.Name("VideoDurationUpdate"), object: eventData)

            }
        case "loadedTimeRanges":
            if let currentItem = player.currentItem {
                let bufferedTime = currentItem.loadedTimeRanges.first?.timeRangeValue.duration.seconds ?? 0
                let eventData: [String: Any] = [
                    "buffering": bufferedTime,
                    
                ]
                NotificationCenter.default.post(name: Notification.Name("VideoDurationUpdate"), object: eventData)
            

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
        NotificationCenter.default.removeObserver(self, name: Notification.Name("SeekToTimeNotification"), object: nil)

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

    // UICollectionView DataSource

    // UICollectionView DelegateFlowLayout to define size of each cell


    // Play video when it comes into view


    //     func scrollViewDidScroll(_ scrollView: UIScrollView) {
    //     for (index, playerView) in playerViews.enumerated() {
    //         let cellRect = collectionView.layoutAttributesForItem(at: IndexPath(row: index, section: 0))?.frame ?? .zero
    //         let intersection = cellRect.intersection(scrollView.bounds)
    //         let visibilityRatio = intersection.width * intersection.height / cellRect.width / cellRect.height

    //         // If less than 100% visible, pause the video
    //         if visibilityRatio < 0.99 {
    //             playerView.pause()
    //         } else {
    //             // Otherwise, play the video
    //             playerView.play()
    //         }
    //     }
    // }
}


