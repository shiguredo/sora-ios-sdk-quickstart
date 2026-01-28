import Sora
import UIKit
import os

private let logger = Logger(
  subsystem: "jp.shiguredo.sora-ios-sdk-quickstart",
  category: "ViewController"
)

class ViewController: UIViewController {
  @IBOutlet weak var senderVideoView: VideoView!
  @IBOutlet weak var receiverVideoView: VideoView!
  @IBOutlet weak var connectImageView: UIImageView!
  // 接続/切断処理中はタップを無効化するための Gesture Recognizer (タッチ処理制御)です
  @IBOutlet private weak var connectTapGestureRecognizer: UITapGestureRecognizer?

  // 接続状態の管理用 Enum です。
  private enum ConnectionState {
    case idle
    case connecting
    case connected
    case disconnecting
  }

  // 接続処理の直列化用の DispatchQueue です。
  private let connectionQueue = DispatchQueue(
    label: "jp.shiguredo.sora-ios-sdk-quickstart.connectionQueue"
  )

  private var connectionState: ConnectionState = .idle
  private var connectTimeoutWorkItem: DispatchWorkItem?
  // quickstart 側での Sora 接続試行のタイムアウト (秒) です
  private let connectTimeoutSeconds: TimeInterval = 15

  // 接続済みの MediaChannel です。
  var mediaChannel: MediaChannel?

  // 接続試行中のタスクです。
  var connectionTask: ConnectionTask?

  override func viewDidLoad() {
    super.viewDidLoad()
    Logger.shared.level = .debug
    Sora.setWebRTCLogLevel(.info)

    navigationItem.title = "\(Environment.channelId)"
    updateUIForState()
  }

  // 接続ボタンの UI を更新します。
  private func updateUIForState() {
    DispatchQueue.main.async {
      let isInteractive = self.connectionState == .idle || self.connectionState == .connected
      self.connectTapGestureRecognizer?.isEnabled = isInteractive

      if self.connectionState == .idle {
        // 未接続時の処理です。
        self.connectImageView.image = UIImage(systemName: "play.circle.fill")
        self.connectImageView.tintColor = .systemGreen
      } else {
        // 接続中/接続済み/切断中の処理です。
        self.connectImageView.image = UIImage(systemName: "stop.circle.fill")
        self.connectImageView.tintColor = .systemRed
      }
    }
  }

  @IBAction func connect(_ sender: AnyObject) {
    connectionQueue.async { [weak self] in
      guard let self else { return }
      switch self.connectionState {
      case .idle:
        // 未接続なら接続します。
        self.startConnectOnConnectionQueue()
      case .connecting:
        // 接続中は完了するまで無視します。
        logger.debug("接続処理中のためタップを無視します")
      case .connected:
        // 接続済みなら接続を解除します。
        self.startDisconnectOnConnectionQueue()
      case .disconnecting:
        // 切断中の連打は無視します。
        logger.debug("切断処理中のためタップを無視します")
      }
    }
  }

  // Sora 接続を行います。
  // connectionQueue 上で実行されます。
  private func startConnectOnConnectionQueue() {
    guard connectionState == .idle else {
      return
    }

    connectionState = .connecting
    updateUIForState()
    scheduleConnectTimeoutOnConnectionQueue()

    // 接続の設定を行います。
    var config = Configuration(
      url: Environment.url,
      channelId: Environment.channelId,
      role: .sendrecv)

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
        DispatchQueue.main.async {
          stream.videoRenderer = strongSelf.receiverVideoView
        }
      }
    }
    // 切断通知（onDisconnect）を受けたときの処理です
    config.mediaChannelHandlers.onDisconnect = { [weak self] event in
      guard let strongSelf = self else {
        return
      }
      strongSelf.connectionQueue.async { [weak self] in
        guard let self else { return }
        guard self.connectionState != .idle else {
          return
        }

        self.cancelConnectTimeoutOnConnectionQueue()

        switch event {
        case .ok(let code, let reason):
          logger.info("接続解除: ステータスコード: \(code), 理由: \(reason)")
        case .error(let error):
          let message = error.localizedDescription
          logger.error("接続エラー: \(message)")
          DispatchQueue.main.async { [weak self] in
            let alertController = UIAlertController(
              title: "接続エラーが発生しました",
              message: message,
              preferredStyle: .alert)
            alertController.addAction(
              UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self?.present(alertController, animated: true, completion: nil)
          }
        }

        self.connectionTask = nil
        self.mediaChannel = nil
        self.connectionState = .idle
        self.updateUIForState()
      }
    }

    // Sora へ接続します。
    // connect() の戻り値 ConnectionTask を使うと
    // 接続試行中の状態を強制的に終了させることができます。
    connectionTask = Sora.shared.connect(configuration: config) { [weak self] mediaChannel, error in
      guard let self else { return }
      self.connectionQueue.async { [weak self] in
        guard let self else { return }
        // タイムアウトで .idle に戻った後、遅れて成功が返ってきた場合は採用せず切断します
        guard self.connectionState == .connecting else {
          if let mediaChannel {
            mediaChannel.disconnect(error: nil)
          }
          return
        }

        // 接続処理結果が返ってきたためタイムアウト予約をキャンセルします
        self.cancelConnectTimeoutOnConnectionQueue()
        self.connectionTask = nil

        // 接続に失敗するとエラーが渡されます。
        if let error {
          let message = error.localizedDescription
          logger.error("接続失敗: \(message)")
          DispatchQueue.main.async { [weak self] in
            let alertController = UIAlertController(
              title: "接続に失敗しました",
              message: message,
              preferredStyle: .alert)
            alertController.addAction(
              UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self?.present(alertController, animated: true, completion: nil)
          }
          self.connectionState = .idle
          self.updateUIForState()
          return
        }

        guard let mediaChannel else {
          logger.error("接続失敗: MediaChannel が nil です")
          self.connectionState = .idle
          self.updateUIForState()
          return
        }

        // 接続に成功した MediaChannel を保持しておきます。
        self.mediaChannel = mediaChannel
        self.connectionState = .connected
        self.updateUIForState()

        // 接続できたら配信用の VideoView をストリームにセットします。
        if let stream = mediaChannel.senderStream {
          DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            stream.videoRenderer = self.senderVideoView
          }
        }
      }
    }
  }

  // Sora 切断処理を行います。
  // connectionQueue 上で実行されます。
  private func startDisconnectOnConnectionQueue() {
    // 接続確立済み、以外であれば抜けます
    guard connectionState == .connected else {
      return
    }

    connectionState = .disconnecting
    updateUIForState()
    cancelConnectTimeoutOnConnectionQueue()

    mediaChannel?.disconnect(error: nil)
    mediaChannel = nil
  }

  // quickstart 側の接続タイムアウトをスケジューリングします。
  // connectionQueue 上で実行されます。
  private func scheduleConnectTimeoutOnConnectionQueue() {
    // 古いタイムアウト予約をキャンセルします
    cancelConnectTimeoutOnConnectionQueue()

    let seconds = Int(connectTimeoutSeconds)
    // connectTimeoutSeconds 秒後に実行される DispatchWorkItem を作成します
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      // connecting 以外なら何もしない
      guard self.connectionState == .connecting else { return }

      // タイムアウト確定のため、接続に関するリソースをリセットします
      self.connectTimeoutWorkItem = nil

      let task = self.connectionTask
      self.connectionTask = nil
      self.mediaChannel = nil
      self.connectionState = .idle
      self.updateUIForState()

      // Sora SDK 側の connect 処理をキャンセルします
      task?.cancel()

      // 接続失敗のポップアップを表示します
      // UI 操作のためメインスレッドで実行します
      DispatchQueue.main.async { [weak self] in
        let alertController = UIAlertController(
          title: "接続に失敗しました",
          message: "接続がタイムアウトしました（\(seconds)秒）。",
          preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
        self?.present(alertController, animated: true, completion: nil)
      }
    }

    connectTimeoutWorkItem = workItem
    // connectTimeoutSeconds 秒後に実行するように asyncAfter で予約します
    connectionQueue.asyncAfter(deadline: .now() + connectTimeoutSeconds, execute: workItem)
  }

  // タイムアウト予約をキャンセルします。
  // 古いタイムアウト予約が残ってしまうような場合に関係のないタイムアウトポップアップ表示を防ぎます。
  // connectionQueue 上で実行されます。
  private func cancelConnectTimeoutOnConnectionQueue() {
    connectTimeoutWorkItem?.cancel()
    connectTimeoutWorkItem = nil
  }
}
