import Sora
import UIKit

class ViewController: UIViewController {
  @IBOutlet weak var senderVideoView: VideoView!
  @IBOutlet weak var remoteVideoContainerView: UIView!
  @IBOutlet weak var connectImageView: UIImageView!

  // 接続済みの MediaChannel です。
  var mediaChannel: MediaChannel?

  // 接続試行中にキャンセルするためのオブジェクトです。
  var connectionTask: ConnectionTask?

  // 接続済みであれば true を返します。
  var connecting: Bool {
    mediaChannel?.isAvailable == true
  }

  // 音声メトリクス表示用
  private let audioManager = SoraAudioManager()
  private let metricsLabel = UILabel()
  private var metricsTimer: Timer?
  private var remoteVideoViews: [String: VideoView] = [:]
  private var remoteStreamOrder: [String] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    Logger.shared.level = .debug
    Sora.setWebRTCLogLevel(.info)

    navigationItem.title = "\(Environment.channelId)"

    remoteVideoContainerView.clipsToBounds = true
    setupMetricsLabel()
    startMetricsTimer()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutRemoteVideoViews()
  }

  deinit {
    metricsTimer?.invalidate()
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

  func loadCACertificate(fromBundle filename: String) -> SecCertificate? {
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

    clearRemoteVideoViews()

    if let caCertificate = loadCACertificate(fromBundle: Environment.caCertFilename) {
      NSLog("CA 証明書の読み込みに成功しました")
      //config.caCertificate = caCertificate
    }

    // ストリームが追加されたら受信用の VideoView をストリームにセットします。
    // 複数ユーザーが接続された場合でも、それぞれの映像を専用の VideoView に割り当てます。
    let publisherStreamId = config.publisherStreamId
    config.mediaChannelHandlers.onAddStream = { [weak self] stream in
      guard let strongSelf = self else {
        return
      }
      if stream.streamId != publisherStreamId {
        strongSelf.attachRemoteVideo(stream)
      }
    }
    config.mediaChannelHandlers.onRemoveStream = { [weak self] stream in
      guard let strongSelf = self else {
        return
      }
      if stream.streamId != publisherStreamId {
        strongSelf.detachRemoteVideo(stream)
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
      self?.clearRemoteVideoViews()
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
        self.clearRemoteVideoViews()
        return
      }

      // 接続に成功した MediaChannel を保持しておきます。
      self.mediaChannel = mediaChannel

      // 音声処理をセットアップ（AudioSink の追加など）
      if let mc = mediaChannel {
        self.audioManager.setupWithMediaChannel(mc)
      }

      // 接続できたら配信用の VideoView をストリームにセットします。
      if let stream = mediaChannel!.senderStream {
        stream.videoRenderer = self.senderVideoView
      }
    }
  }

  private func attachRemoteVideo(_ stream: MediaStream) {
    let streamId = stream.streamId
    DispatchQueue.main.async {
      if let existingView = self.remoteVideoViews[streamId] {
        stream.videoRenderer = existingView
        return
      }

      let videoView = VideoView(frame: self.remoteVideoContainerView.bounds)
      videoView.autoresizingMask = []
      videoView.clipsToBounds = true
      self.remoteVideoContainerView.addSubview(videoView)
      self.remoteVideoViews[streamId] = videoView
      self.remoteStreamOrder.append(streamId)
      stream.videoRenderer = videoView
      self.view.setNeedsLayout()
      self.layoutRemoteVideoViews()
    }
  }

  private func detachRemoteVideo(_ stream: MediaStream) {
    let streamId = stream.streamId
    DispatchQueue.main.async {
      stream.videoRenderer = nil
      if let videoView = self.remoteVideoViews.removeValue(forKey: streamId) {
        videoView.removeFromSuperview()
      }
      if let index = self.remoteStreamOrder.firstIndex(of: streamId) {
        self.remoteStreamOrder.remove(at: index)
      }
      self.view.setNeedsLayout()
      self.layoutRemoteVideoViews()
    }
  }

  private func clearRemoteVideoViews() {
    DispatchQueue.main.async {
      for videoView in self.remoteVideoViews.values {
        videoView.removeFromSuperview()
      }
      self.remoteVideoViews.removeAll()
      self.remoteStreamOrder.removeAll()
      self.view.setNeedsLayout()
      self.layoutRemoteVideoViews()
    }
  }

  private func layoutRemoteVideoViews() {
    let containerBounds = remoteVideoContainerView.bounds
    guard containerBounds.width > 0, containerBounds.height > 0 else {
      return
    }

    let views = remoteStreamOrder.compactMap { remoteVideoViews[$0] }

    guard !views.isEmpty else {
      return
    }

    let count = views.count
    let columns = Int(ceil(sqrt(Double(count))))
    let rows = Int(ceil(Double(count) / Double(columns)))
    let spacing: CGFloat = 4.0
    let totalSpacingX = spacing * CGFloat(max(columns - 1, 0))
    let totalSpacingY = spacing * CGFloat(max(rows - 1, 0))
    let cellWidth = (containerBounds.width - totalSpacingX) / CGFloat(columns)
    let cellHeight = (containerBounds.height - totalSpacingY) / CGFloat(rows)

    for (index, view) in views.enumerated() {
      let row = index / columns
      let column = index % columns
      let originX = CGFloat(column) * (cellWidth + spacing)
      let originY = CGFloat(row) * (cellHeight + spacing)
      let frame = CGRect(x: originX, y: originY, width: cellWidth, height: cellHeight)
      if view.frame != frame {
        view.frame = frame
      }
    }
  }

  // MARK: - Metrics UI

  private func setupMetricsLabel() {
    metricsLabel.translatesAutoresizingMaskIntoConstraints = false
    metricsLabel.numberOfLines = 0
    metricsLabel.textColor = .white
    metricsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
    metricsLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    metricsLabel.textAlignment = .left
    metricsLabel.layer.cornerRadius = 6
    metricsLabel.clipsToBounds = true
    metricsLabel.text = "metrics: --"
    view.addSubview(metricsLabel)

    // 左上に配置
    NSLayoutConstraint.activate([
      metricsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      metricsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
    ])
  }

  private func startMetricsTimer() {
    metricsTimer?.invalidate()
    metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateMetricsUI()
    }
  }

  private func updateMetricsUI() {
    let m = audioManager.getMetrics()
    let recv = formatBytes(m.receivedBytes)
    let proc = formatBytes(m.processedBytes)
    let avgMs = Int(m.averageLatency * 1000)
    let peakMs = Int(m.peakLatency * 1000)
    let text = "Recv: \(recv)  Proc: \(proc)\nDrop: \(m.droppedFrames)  API: \(m.apiCallCount)\nLat(ms): avg \(avgMs) / peak \(peakMs)"
    metricsLabel.text = text
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024.0
    if kb < 1024 { return String(format: "%.1fKB", kb) }
    let mb = kb / 1024.0
    return String(format: "%.2fMB", mb)
  }
}

class SoraAudioManager {
  private let audioPipeline = HighPerformanceAudioPipeline()
  
  func setupWithMediaChannel(_ channel: MediaChannel) {
    // 既存の onAddStream を保持して連結する
    let previous = channel.handlers.onAddStream
    channel.handlers.onAddStream = { [weak self] stream in
      previous?(stream)
      self?.handleStreamAdded(stream)
    }
  }
  
  private func handleStreamAdded(_ stream: MediaStream) {
      // 各トラックに個別にAudioSinkを追加
      stream.addAudioSink(audioPipeline)
      print("Audio capture started for track: \(stream.streamId)")
  }

  // メトリクスの公開
  func getMetrics() -> HighPerformanceAudioPipeline.AudioProcessingMetrics {
    return audioPipeline.getMetrics()
  }
  func resetMetrics() {
    audioPipeline.resetMetrics()
  }
  func shutdown() {
    audioPipeline.shutdown()
  }
}
