import UIKit
import Sora

// 接続するサーバーのシグナリング URL
let soraURL = URL(string: "ws://192.168.0.4:5000/signaling")!

// チャネル ID
let soraChannelId = "sora"

class ViewController: UIViewController {
    
    @IBOutlet weak var senderVideoView: VideoView!
    @IBOutlet weak var receiverVideoView: VideoView!
    @IBOutlet weak var connectImageView: UIImageView!

    // 接続済みの MediaChannel です。
    var mediaChannel: MediaChannel?

    // 接続試行中にキャンセルするためのオブジェクトです。
    var connectionTask: ConnectionTask?

    // 接続済みであれば true を返します。
    var connecting: Bool {
        mediaChannel?.isAvailable == true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.level = .debug
        
        navigationItem.title = "\(soraChannelId)"
    }

    // 接続ボタンの UI を更新します。
    func updateUI(_ connect: Bool) {
        DispatchQueue.main.async {
            if connect {
                // 接続時の処理です。
                self.connectImageView.image = UIImage(systemName: "stop.circle.fill")
                self.connectImageView.tintColor = .systemRed
            } else {
                // 接続解除時の処理です。
                self.connectImageView.image = UIImage(systemName: "play.circle.fill")
                self.connectImageView.tintColor = .systemGreen
            }
        }
    }

    @IBAction func connect(_ sender: AnyObject) {
        // 接続試行中のタスクが残っていればキャンセルします。
        connectionTask?.cancel()

        if connecting {
            // 接続済みであれば接続を解除します。
            if mediaChannel?.isAvailable == true {
                mediaChannel?.disconnect(error: nil)
            }
            updateUI(false)
        } else {
            // 未接続なら接続します。
            connect()
            updateUI(true)
        }
    }

    func connect() {
        // 接続の設定を行います。
        let config = Configuration(url: soraURL,
                                   channelId: soraChannelId,
                                   role: .sendrecv,
                                   multistreamEnabled: true)

        // 受信した映像を描画する設定を行います。
        // マルチストリームで接続しますが、最初に同チャネルに接続された 1 つの受信ストリームにのみ対応しています。
        config.peerChannelHandlers.onAddStream = { mediaStream in
            mediaStream.videoRenderer = self.receiverVideoView
        }

        // 接続します。
        // connect() の戻り値 ConnectionTask を使うと
        // 接続試行中の状態を強制的に終了させることができます。
        connectionTask = Sora.shared.connect(configuration: config) { mediaChannel, error in
            // 接続に失敗するとエラーが渡されます。
            if let error = error {
                NSLog(error.localizedDescription)
                self.updateUI(false)
                return
            }

            // 接続に成功した MediaChannel を保持しておきます。
            self.mediaChannel = mediaChannel

            // 接続できたら配信用の VideoView をストリームにセットします。
            if let stream = mediaChannel!.senderStream {
                stream.videoRenderer = self.senderVideoView
            }

            // すでに他のユーザーからの接続があれば受信用の VideoView をストリームにセットします。
            // このアプリでは 1 つのストリームのみを描画します。
            if let stream = mediaChannel!.receiverStreams.first {
                stream.videoRenderer = self.receiverVideoView
            }

            // 接続先から接続を解除されたときに行う処理です。
            mediaChannel!.handlers.onDisconnect = { error in
                if let error = error {
                    NSLog(error.localizedDescription)
                }
                self.updateUI(false)
            }
        }
    }

}

