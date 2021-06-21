import UIKit
import Sora

// 接続するサーバーのシグナリング URL
let soraURL = URL(string: "ws://192.168.0.2:5000/signaling")!

// チャネル ID
let soraChannelId = "ios-quickstart"

class ViewController: UIViewController {
    
    @IBOutlet weak var senderVideoView: VideoView!
    @IBOutlet weak var senderConnectButton: UIButton!
    
    @IBOutlet weak var receiverVideoView: VideoView!
    @IBOutlet weak var receiverConnectButton: UIButton!
    
    var senderMediaChannel: MediaChannel?
    var receiverMediaChannel: MediaChannel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.level = .debug
        
        navigationItem.title = "\(soraChannelId)"
    }

    @IBAction func connectSender(_ sender: AnyObject) {
        if let mediaChannel = senderMediaChannel {
            disconnect(mediaChannel: mediaChannel,
                       connectButton: senderConnectButton)
            senderMediaChannel = nil
        } else {
            connect(role: .sendonly,
                    connectButton: senderConnectButton,
                    videoView: senderVideoView)
            { mediaChannel in
                self.senderMediaChannel = mediaChannel
            }
        }
    }
    
    @IBAction func connectReceiver(_ sender: AnyObject) {
        if let mediaChannel = receiverMediaChannel {
            disconnect(mediaChannel: mediaChannel,
                       connectButton: receiverConnectButton)
            receiverMediaChannel = nil
            receiverVideoView.clear()
        } else {
            connect(role: .recvonly,
                    connectButton: receiverConnectButton,
                    videoView: receiverVideoView)
            { mediaChannel in
                self.receiverMediaChannel = mediaChannel

            }
        }
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

