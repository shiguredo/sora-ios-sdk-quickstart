import Sora
import UIKit
import AVFAudio

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
        Sora.setWebRTCLogLevel(.info)

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
            mediaChannel = nil
            updateUI(false)
        } else {
            // 未接続なら接続します。
            connect()
            updateUI(true)
        }
    }

    func connect() {
        // 接続の設定を行います。
        var config = Configuration(url: Environment.url,
                                   channelId: Environment.channelId,
                                   role: .sendrecv,
                                   multistreamEnabled: true)

        // 接続時に指定したいオプションを以下のように設定します。
        config.signalingConnectMetadata = Environment.signalingConnectMetadata

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
            if let error {
                NSLog(error.localizedDescription)
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: "接続に失敗しました",
                                                            message: error.localizedDescription,
                                                            preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                    self?.present(alertController, animated: true, completion: nil)
                }
            }
            strongSelf.updateUI(false)
        }

        // 接続します。
        // connect() の戻り値 ConnectionTask を使うと
        // 接続試行中の状態を強制的に終了させることができます。
        connectionTask = Sora.shared.connect(configuration: config) { mediaChannel, error in
            // 接続に失敗するとエラーが渡されます。
            if let error {
                NSLog(error.localizedDescription)
                DispatchQueue.main.async { [weak self] in
                    let alertController = UIAlertController(title: "接続に失敗しました",
                                                            message: error.localizedDescription,
                                                            preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                    self?.present(alertController, animated: true, completion: nil)
                }
                self.updateUI(false)
                return
            }

            // 接続に成功した MediaChannel を保持しておきます。
            self.mediaChannel = mediaChannel

            // 接続できたら配信用の VideoView をストリームにセットします。
            if let stream = mediaChannel!.senderStream {
                stream.videoRenderer = self.senderVideoView
            }
        }
        // AVAudioSession の設定を行います。
        Sora.shared.configureAudioSession(block: configureStereoAudio)
    }

    func configureStereoAudio() -> Void {
        let audioSession = AVAudioSession.sharedInstance()

        if (audioSession.maximumInputNumberOfChannels < 2) {
            print("オーディオルートで使用可能な入力チャンネルの最大数が 2 未満でした: \(audioSession.maximumInputNumberOfChannels)")
            return
        }

        // 入力チャンネル数を 2 に設定する
        do {
            try audioSession.setPreferredInputNumberOfChannels(2)
            // 設定が変更されたかチェック
            if (audioSession.inputNumberOfChannels != 2) {
                print("入力チャンネル数が 2 に設定されませんでした: \(audioSession.inputNumberOfChannels)")
                return
            }
            print("入力チャンネル数を 2 に設定しました")
        } catch {
            print("エラー発生: \(error.localizedDescription)")
        }
    }
}
