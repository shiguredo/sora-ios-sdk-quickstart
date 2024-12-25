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

    /// dataChannels の label ごとにヘッダーの長さを保持するための変数
    var headerLengths: [String: Int] = [:]

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

        // DataChannel 経由のシグナリングを有効にする
        config.dataChannelSignaling = true

        // メッセージング機能に利用する DataChannel を指定する
        config.dataChannels = [[
            "label": "#spam",
            "direction": "recvonly",
        ], [
            "label": "#egg",
            "max_retransmits": 0,
            "ordered": false,
            "protocol": "abc",
            "compress": false,
            "direction": "recvonly",
            "header": [
                ["type": "sender_connection_id"],
            ],
        ]]

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

        // offer で入ってくる data channel header の長さを取得する
        config.mediaChannelHandlers.onReceiveSignaling = { [weak self] signaling in
            guard let self else {
                return
            }
            switch signaling {
            case let .offer(offer):
                guard let dataChannels = offer.dataChannels else {
                    return
                }
                for dataChannel in dataChannels {
                    // ラベルが "#" で始まる場合のみ処理する
                    let label: String = dataChannel["label"] as! String
                    guard label.starts(with: "#") else {
                        continue
                    }

                    // dataChannel["header"] が nil ではない場合のみ後続処理を行う
                    guard let headers = dataChannel["header"] as? [[String: Any]] else {
                        continue
                    }
                    for header in headers {
                        if header["type"] as! String == "sender_connection_id" {
                            let length = header["length"] as! Double
                            headerLengths[label] = Int(length)
                            print("kensaku: \(label) \(Int(length))")
                        }
                    }
                }
            default:
                break
            }
        }
        // メッセージ受信時の挙動を定義します。
        config.mediaChannelHandlers.onDataChannelMessage = { [weak self] _, label, data in
            guard let weakSelf = self else {
                return
            }

            // "#" で始まるラベル以外は無視します
            guard label.starts(with: "#") else {
                return
            }

            // ヘッダーの長さを取得し、ヘッダーとメッセージを分離します
            let headerLength = weakSelf.headerLengths[label] ?? 0
            if headerLength == 0 {
                print(String(data: data, encoding: .utf8) ?? data.map(\.description).joined(separator: ", "))
                return
            }

            let header = data.prefix(headerLength)
            let message = data.suffix(from: headerLength)
            print("kensaku: \(String(data: header, encoding: .utf8) ?? header.map(\.description).joined(separator: ", "))")
            print("kensaku: \(String(data: message, encoding: .utf8) ?? message.map(\.description).joined(separator: ", "))")
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
    }
}
