import UIKit
import AVFoundation

class VideoPlayerCollectionViewCell: UICollectionViewCell {
    
    private var playerView: VideoPlayerUIView!
    
    // Configure the cell with a URL for video playback
    func configure(with videoURL: URL) {
        if playerView == nil {
            playerView = VideoPlayerUIView(frame: self.contentView.bounds, videoURL: videoURL)
            self.contentView.addSubview(playerView)
        } else {
            playerView.changeVideo(to: videoURL)  // If player view already exists, just change video
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerView.frame = self.contentView.bounds  // Ensure player view fills the cell
    }
}
