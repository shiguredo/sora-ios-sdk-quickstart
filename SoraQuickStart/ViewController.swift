import UIKit
import Sora

// 接続するサーバーのシグナリング URL
let soraURL = URL(string: "ws://192.168.0.2:5000/signaling")!

// チャネル ID
let soraChannelId = "ios-quickstart"

class ViewController: UIViewController {

    @IBOutlet weak var publisherVideoView: VideoView!
    @IBOutlet weak var subscriberVideoView: VideoView!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    
    var publisher: MediaChannel!
    var subscriber: MediaChannel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        connectButton.isEnabled = true
        disconnectButton.isEnabled = false
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func connect(_ sender: AnyObject) {
        connectButton.isEnabled = false
        disconnectButton.isEnabled = false
        
        // シグナリング URL とチャネル ID を指定する
        let pubConfig = Configuration(url: soraURL,
                                      channelId: soraChannelId,
                                      role: .publisher)
        
        // パブリッシャーを接続する
        let _ = Sora.shared.connect(configuration: pubConfig) { pub, error in
            // 接続に失敗するとエラーが渡される。
            // 接続に成功すると error は nil
            if let error = error {
                print(error.localizedDescription)
                DispatchQueue.main.async {
                    self.connectButton.isEnabled = true
                }
                return
            }
            
            // サブスクライバーを接続する
            let subConfig = Configuration(url: soraURL,
                                          channelId: soraChannelId,
                                          role: .subscriber)
            let _ = Sora.shared.connect(configuration: subConfig) {
                sub, error in
                if let error = error {
                    print(error.localizedDescription)
                    DispatchQueue.main.async {
                        self.connectButton.isEnabled = true
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.disconnectButton.isEnabled = true
                }
                
                // 映像を描画するビューをストリームにセットする
                self.publisher = pub
                self.publisher.mainStream!.videoRenderer = self.publisherVideoView
                self.subscriber = sub
                self.subscriber.mainStream!.videoRenderer = self.subscriberVideoView
            }
        }
    }
    
    @IBAction func disconnect(_ sender: AnyObject) {
        publisher.disconnect(error: nil)
        subscriber.disconnect(error: nil)
        self.connectButton.isEnabled = true
        self.disconnectButton.isEnabled = false
    }
    
    @IBAction func switchCameraPosition(_ sender: AnyObject) {
        if disconnectButton.isEnabled {
            CameraVideoCapturer.shared.flip()
        }
    }
    
}

