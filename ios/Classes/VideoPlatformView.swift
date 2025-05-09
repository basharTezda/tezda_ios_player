import Flutter
import UIKit


class VideoPlatformView: NSObject, FlutterPlatformView {
    private let playerView: VideoPlayerUIView
    
    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) {
        let url: URL
        let isMuted: Bool
        let isLandScape: Bool
        if let dict = args as? [String: Any],
            let urlStr = dict["url"] as? String,
           let mute = dict["shouldMute"] as? Bool,
           let isLandScapeFromDict = dict["isLandscape"] as? Bool,
            let parsed = URL(string: urlStr)
        {
            url = parsed
            isMuted = mute
            isLandScape = isLandScapeFromDict
        } else {
            url = URL(
                string:
                    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"
            )!
            isMuted = false
            isLandScape = false
        }

        playerView = VideoPlayerUIView(frame: frame, videoURL: url,isMuted: isMuted,isLandScape: isLandScape)

        super.init()



    }

    func view() -> UIView {

        return playerView
    }
}
