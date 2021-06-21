import UIKit
import Sora

// 接続するサーバーのシグナリング URL
let soraURL = URL(string: "ws://192.168.0.2:5000/signaling")!

// チャネル ID
let soraChannelId = "sora"

class ViewController: UIViewController {
    
    @IBOutlet weak var senderVideoView: VideoView!
    @IBOutlet weak var receiverVideoView: VideoView!
    @IBOutlet weak var connectImageView: UIImageView!
    
    var senderMediaChannel: MediaChannel?
    var receiverMediaChannel: MediaChannel?
    var connecting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.level = .debug
        
        navigationItem.title = "\(soraChannelId)"
    }

    @IBAction func connect(_ sender: AnyObject) {
        if connecting {
            connectImageView.image = UIImage(systemName: "play.circle.fill")
            connectImageView.tintColor = .systemGreen

        } else {
            connectImageView.image = UIImage(systemName: "stop.circle.fill")
            connectImageView.tintColor = .systemRed
        }
        connecting = !connecting
    }

    func connect(role: Role,
                 connectButton: UIButton,
                 videoView: VideoView,
                 completionHandler: @escaping (MediaChannel?) -> Void) {
        DispatchQueue.main.async {
            connectButton.isEnabled = false
        }
        
        // 接続の設定を行います。
        let config = Configuration(url: soraURL,
                                   channelId: soraChannelId,
                                   role: role,
                                   multistreamEnabled: true)

        if role == .recvonly {
            config.peerChannelHandlers.onAddStream = { mediaStream -> Void in
                mediaStream.videoRenderer = videoView
            }
        }
        
        // 接続します。
        // connect() の戻り値 ConnectionTask はここでは使いませんが、
        // 接続試行中の状態を強制的に終了させることができます。
        let _ = Sora.shared.connect(configuration: config) { mediaChannel, error in
            // 接続に失敗するとエラーが渡されます。
            if let error = error {
                print(error.localizedDescription)
                DispatchQueue.main.async {
                    connectButton.isEnabled = true
                }
                completionHandler(nil)
                return
            }
            
            // 接続できたら VideoView をストリームにセットします。
            // マルチストリームの場合、最初に接続したストリームが mainStream です。
            // 受信専用で接続したとき、何も配信されていなければ mainStream は nil です。
            if let stream = mediaChannel!.mainStream {
                stream.videoRenderer = videoView
            }
            
            DispatchQueue.main.async {
                connectButton.isEnabled = true
                connectButton.setImage(UIImage(systemName: "stop.fill"),
                                       for: .normal)
            }
            
            completionHandler(mediaChannel!)
        }
    }
    
    func disconnect(mediaChannel: MediaChannel, connectButton: UIButton) {
        if mediaChannel.isAvailable {
            // 接続解除します。
            mediaChannel.disconnect(error: nil)
        }
        
        DispatchQueue.main.async {
            connectButton.setImage(UIImage(systemName: "play.fill"),
                                   for: .normal)
        }
    }
    
}

