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
    var config = Configuration(
      url: Environment.url,
      channelId: Environment.channelId,
      role: .sendrecv,
      multistreamEnabled: true)

    // Configured with the specified settings
    config.connectionTimeout = 60
    config.cameraSettings.isEnabled = false
    config.cameraSettings.resolution = .hd720p
    config.cameraSettings.frameRate = 30
    config.videoBitRate = 3_000
    config.webRTCConfiguration.degradationPreference = .maintainResolution
    config.videoCodec = .vp9
    config.audioEnabled = true
    config.audioCodec = .opus
    config.audioBitRate = 384
    config.signalingConnectMetadata = ["access_token": "MyAccessToken"]
    config.clientId = "iphone-\(UIDevice.current.identifierForVendor?.uuidString ?? "")"

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
        let errorMessage = self?.handleErrorMessage(error)
        DispatchQueue.main.async {
          let alertController = UIAlertController(
            title: errorMessage?.title,
            message: errorMessage?.message,
            preferredStyle: .alert)
          alertController.addAction(
            UIAlertAction(title: "OK", style: .cancel, handler: nil))
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
          let alertController = UIAlertController(
            title: "接続に失敗しました",
            message: error.localizedDescription,
            preferredStyle: .alert)
          alertController.addAction(
            UIAlertAction(title: "OK", style: .cancel, handler: nil))
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

  private func handleErrorMessage(_ error: Error) -> (
    title: String, message: String
  ) {
    var title: String
    var message: String
    if let soraError = error as? SoraError {
      switch soraError {
      case .webSocketClosed(let code, let reason):
        title = "Sora から切断されました"
        message = "ステータスコード: \(code.intValue()), 理由: \(reason ?? "不明")"
      default:
        title = "接続に失敗しました"
        message = error.localizedDescription
      }
    } else {
      title = "接続に失敗しました"
      message = error.localizedDescription
    }
    return (title, message)
  }
}
