import Foundation
import Sora
import SwiftUI

struct Video: UIViewRepresentable {
    typealias UIViewType = VideoView

    @Binding var stream: MediaStream?
    @Binding var rendering: Bool

    func makeUIView(context: Context) -> VideoView {
        NSLog("\(#function)")
        let view = VideoView()
        view.start()
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        NSLog("\(#function)")

        // TODO: これだと毎度 renderer がセットされてしまって無駄？
        if let stream = stream {
            stream.videoRenderer = uiView
        }

        if rendering {
            if uiView.isRendering {
                uiView.stop()
            }
        } else if !uiView.isRendering {
            uiView.start()
        }
    }

    // TODO: 不要？
    /*
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }

     final class Coordinator {
         var video: Video

         init(_ video: Video) {
             self.video = video
         }
     }
     */
}
