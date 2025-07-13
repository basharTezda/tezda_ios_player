import Flutter
import UIKit

class VideoPlatformView: NSObject, FlutterPlatformView {
    private let playerView: VideoPlayerUIView
    private let staticUrl: URL = URL(string: "https://commondatastorage.googleapislkdsajfklajslkfjsa.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4")!
    
    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?,   binaryMessenger messenger: FlutterBinaryMessenger) {
        // Default values
        var url: URL = staticUrl
        var isMuted: Bool = false
        var isLandScape: Bool = false
        var preLoad: [String]!
        
        if let dict = args as? [String: Any] {
            // Validate main URL
            if let urlStr = dict["url"] as? String,
               let validatedUrl = VideoPlatformView.validateURL(urlStr) {
                url = validatedUrl
            } else {
                print("Invalid main video URL, using fallback")
            }
            
            // Validate preload URL
            if let preLoadStr = dict["preLoadUrls"] as? [String]
               {
                preLoad = preLoadStr
            }
            
            // Get other parameters
            isMuted = dict["shouldMute"] as? Bool ?? false
            isLandScape = dict["isLandscape"] as? Bool ?? false
        }
        
        playerView = VideoPlayerUIView(
            frame: frame,
            videoURL: url,
            isMuted: isMuted,
            isLandScape: isLandScape,
            nextVideos: preLoad ?? [],  binaryMessenger: messenger
        )
        
        super.init()
    }
    
    func view() -> UIView {
        return playerView
    }
    
    // MARK: - URL Validation
    private static func validateURL(_ urlString: String) -> URL? {
        // Basic URL structure validation
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        
        // Additional validation if needed
        if !isReachableURL(url) {
            print("URL is not reachable: \(urlString)")
            return nil
        }
        
        return url
    }
    
    private static func isReachableURL(_ url: URL) -> Bool {
        // Add any specific domain validation if needed
        return true // Default to true unless you need specific checks
    }
}
