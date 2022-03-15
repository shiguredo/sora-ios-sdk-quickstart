import Sora
import UIKit

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

        navigationItem.title = "\(Environment.channelId)"
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

            // ボタンのタップを有効に戻します。
            self.connectImageView.isUserInteractionEnabled = true
        }
    }

    @IBAction func connect(_ sender: AnyObject) {
        // 処理が終わるまで一時的にボタンのタップを無効にします。
        connectImageView.isUserInteractionEnabled = false
        connectImageView.tintColor = .systemGray

        // 接続試行中のタスクが残っていればキャンセルします。
        connectionTask?.cancel()
        connectionTask = nil

        if connecting {
            // 接続済みであれば接続を解除します。
            if mediaChannel?.isAvailable == true {
                mediaChannel?.disconnect(error: nil)
            }
            mediaChannel = nil
            updateUI(false)
        } else {
            // 未接続なら接続します。
            connect()

            // 現在の SDK のバージョンでは、接続開始直後のキャンセルは
            // クラッシュする可能性があるので、 UI の更新を少し遅らせます
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                if mediaChannel?.isAvailable == true {
                    updateUI(true)
                }
            }
        }
    }

    func connect() {
        // 接続の設定を行います。
        let config = Configuration(url: Environment.url,
                                   channelId: Environment.channelId,
                                   role: .sendrecv,
                                   multistreamEnabled: true)

        // ストリームが追加されたら受信用の VideoView をストリームにセットします。
        // このアプリでは、複数のユーザーが接続した場合は最後のユーザーの映像のみ描画します。
        let publisherStreamId = config.publisherStreamId
        config.mediaChannelHandlers.onAddStream = { [weak self] stream in
            guard let strongSelf = self else {
                return
            }
            if stream.streamId != publisherStreamId {
                stream.videoRenderer = strongSelf.receiverVideoView
            }
        }
        // 接続先から接続を解除されたときに行う処理です。
        config.mediaChannelHandlers.onDisconnect = { [weak self] error in
            guard let strongSelf = self else {
                return
            }
            if let error = error {
                NSLog(error.localizedDescription)
            }
            strongSelf.updateUI(false)
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

            // 接続完了後にボタンの画像を変更します。
            self.updateUI(true)
        }
    }
}
