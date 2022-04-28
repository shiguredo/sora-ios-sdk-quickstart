import Foundation
import Sora
import SwiftUI
import UIKit

public struct Video: UIViewRepresentable {
    public typealias UIViewType = VideoView

    @ObservedObject private var model: VideoModel

    public init(_ model: VideoModel) {
        self.model = model
    }

    public func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        context.coordinator.video.model.videoView = view
        view.start()
        return view
    }

    public func updateUIView(_ uiView: VideoView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator {
        var video: Video

        init(_ video: Video) {
            self.video = video
        }
    }
}

public class VideoModel: ObservableObject {
    public var stream: MediaStream? {
        didSet {
            stream?.videoRenderer = videoView
        }
    }

    public var connectionMode: VideoViewConnectionMode = .autoClear {
        didSet {
            videoView?.connectionMode = connectionMode
        }
    }

    public var debugMode: Bool = false {
        didSet {
            videoView?.debugMode = debugMode
        }
    }

    public var backgroundView: UIView? {
        didSet {
            videoView?.backgroundView = backgroundView
        }
    }

    public var currentVideoFrameSize: CGSize? {
        videoView?.currentVideoFrameSize
    }

    public var videoView: VideoView?

    @Published public var isRendering: Bool = true

    public init() {}

    public func start() {
        videoView?.start()
        isRendering = true
    }

    public func stop() {
        videoView?.stop()
        isRendering = false
    }

    public func clear() {
        videoView?.clear()
    }
}
