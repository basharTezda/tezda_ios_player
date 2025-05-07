import Flutter
import UIKit

class VideoPlatformView: NSObject, FlutterPlatformView, UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout
{

    private var collectionView: UICollectionView!
    private var videoURLs: [URL] = []
    private var playerViews: [VideoPlayerUIView] = []  // Hold player views for each video

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) {

        if let dict = args as? [String: Any], let urlStrings = dict["urls"] as? [String] {
            videoURLs = urlStrings.compactMap { URL(string: $0) }
        }

        // Set up UICollectionView to display videos
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0  // Optional: remove line spacing between cells
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: frame, collectionViewLayout: layout)
        collectionView.register(
            VideoPlayerCollectionViewCell.self, forCellWithReuseIdentifier: "VideoPlayerCell")
        collectionView.contentInset = .zero
        collectionView.scrollIndicatorInsets = .zero
        super.init()
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isPagingEnabled = true
        // To simulate TikTok scroll effect

        // Add collection view to the platform view
        collectionView.frame = frame
        collectionView.backgroundColor = .black


    }

    func view() -> UIView {
        return collectionView
    }

    // UICollectionView DataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
        -> Int
    {
        return videoURLs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let cell =
            collectionView.dequeueReusableCell(
                withReuseIdentifier: "VideoPlayerCell", for: indexPath)
            as! VideoPlayerCollectionViewCell
        let videoURL = videoURLs[indexPath.row]
        cell.configure(with: videoURL)
        return cell
    }

    // UICollectionView DelegateFlowLayout to define size of each cell
    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        return CGSize(width: collectionView.frame.width, height: collectionView.frame.height)  // Full-screen videos
    }

    // Play video when it comes into view
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let indexPath = collectionView.indexPathForItem(at: scrollView.contentOffset)
        if let index = indexPath?.row {
            // Play the video when the user scrolls to it

            // playerViews[index].play()
        }
    }

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
