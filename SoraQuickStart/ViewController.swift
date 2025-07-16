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

  func loadCACertificateFromBundle(filename: String) -> SecCertificate? {
    // 1. Bundleからファイルパスを取得
    guard let certPath = Bundle.main.path(forResource: filename, ofType: "pem") else {
      print("Certificate file not found")
      return nil
    }

    // 2. ファイル内容を文字列として読み込み
    guard let pemString = try? String(contentsOfFile: certPath) else {
      print("Failed to read certificate file")
      return nil
    }

    // 3. PEM形式からDER形式に変換
    guard let derData = convertPEMToDER(pemString: pemString) else {
      print("Failed to convert PEM to DER")
      return nil
    }

    // 4. SecCertificateを作成
    return SecCertificateCreateWithData(nil, derData as CFData)
  }

  func convertPEMToDER(pemString: String) -> Data? {
    // PEMヘッダーとフッターを除去
    let lines = pemString.components(separatedBy: .newlines)
    let base64Lines = lines.filter { line in
      !line.hasPrefix("-----BEGIN") && !line.hasPrefix("-----END")
        && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    let base64String = base64Lines.joined()
    return Data(base64Encoded: base64String)
  }

  func connect() {
    // 接続の設定を行います。
    var config = Configuration(
      url: Environment.url,
      channelId: Environment.channelId,
      role: .sendrecv,
      multistreamEnabled: true)

    // 接続時に指定したいオプションを以下のように設定します。
    config.signalingConnectMetadata = Environment.signalingConnectMetadata

    if let caCertificate = loadCACertificateFromBundle(filename: Environment.caCertFilename) {
      NSLog("CA 証明書の読み込みに成功しました")
      config.caCertificate = caCertificate
    }

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
    config.mediaChannelHandlers.onDisconnect = { [weak self] event in
      guard let strongSelf = self else {
        return
      }
      switch event {
      case .ok(let code, let reason):
        NSLog("接続解除: ステータスコード: \(code), 理由: \(reason)")
      case .error(let error):
        NSLog(error.localizedDescription)
        DispatchQueue.main.async {
          let alertController = UIAlertController(
            title: "接続エラーが発生しました",
            message: error.localizedDescription,
            preferredStyle: .alert)
          alertController.addAction(
            UIAlertAction(title: "OK", style: .cancel, handler: nil))
          self?.present(alertController, animated: true, completion: nil)
        }
        strongSelf.updateUI(false)
      }
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
}
