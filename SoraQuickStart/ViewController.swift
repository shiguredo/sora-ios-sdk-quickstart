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
  private var disconnectTimeoutWorkItem: DispatchWorkItem?
  // quickstart 側での Sora 接続試行のタイムアウト (秒) です
  private let connectTimeoutSeconds: TimeInterval = 15
  // quickstart 側での Sora 切断待ちのタイムアウト (秒) です
  private let disconnectTimeoutSeconds: TimeInterval = 10

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

  // アラートメッセージのポップアップを表示します。
  // UI 操作のためメインスレッドで実行します
  private func presentAlertMessage(title: String, message: String) {
    DispatchQueue.main.async {
      let alertController = UIAlertController(
        title: title,
        message: message,
        preferredStyle: .alert)
      alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
      self.present(alertController, animated: true, completion: nil)
    }
  }

  // connectionQueue 上でのみ呼び出す前提の汎用タイムアウト処理です。
  private func scheduleTimeoutOnConnectionQueue(
    seconds: TimeInterval,
    workItem: inout DispatchWorkItem?,
    action: @escaping () -> Void
  ) {
    cancelTimeoutOnConnectionQueue(workItem: &workItem)
    let item = DispatchWorkItem(block: action)
    workItem = item
    connectionQueue.asyncAfter(deadline: .now() + seconds, execute: item)
  }

  // connectionQueue 上でのみ呼び出す前提の汎用タイムアウトキャンセル処理です。
  private func cancelTimeoutOnConnectionQueue(workItem: inout DispatchWorkItem?) {
    workItem?.cancel()
    workItem = nil
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
        // onAddStream はメインスレッドで呼ばれる保証がないため、
        // UIKit に紐づく VideoView を videoRenderer として設定する処理はメインスレッドに寄せます。
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
      // onDisconnect はメインスレッド/特定のキューで呼ばれる保証がないため、
      // quickstart 側の状態 (connectionState 等) は connectionQueue で直列化して扱います。
      strongSelf.connectionQueue.async { [weak self] in
        guard let self else { return }
        // 既に後片付け済み (idle) なら何もしません
        guard self.connectionState != .idle else { return }

        self.cancelConnectTimeoutOnConnectionQueue()
        self.cancelDisconnectTimeoutOnConnectionQueue()

        switch event {
        case .ok(let code, let reason):
          logger.info("接続解除: ステータスコード: \(code), 理由: \(reason)")
        case .error(let error):
          let message = error.localizedDescription
          logger.error("接続エラー: \(message)")
          self.presentAlertMessage(title: "接続エラーが発生しました", message: message)
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
        // タイムアウトで .idle に戻った後、遅れて成功が返ってきた場合は採用せず切断します。
        // SDK 側で切断処理の直列化/遅延実行（PeerChannel の lock）により後片付けされるため、
        // disconnect の完了待ちはしません。
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
          self.presentAlertMessage(title: "接続に失敗しました", message: message)
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

    guard mediaChannel != nil else {
      // state と実体がズレている場合は復旧させます
      connectionState = .idle
      updateUIForState()
      return
    }

    connectionState = .disconnecting
    updateUIForState()
    cancelConnectTimeoutOnConnectionQueue()
    scheduleDisconnectTimeoutOnConnectionQueue()

    // MediaChannel の破棄 (self.mediaChannel = nil) は onDisconnect 側で一元的に行います。
    mediaChannel?.disconnect(error: nil)
  }

  // quickstart 側の接続タイムアウトをスケジューリングします。
  // connectionQueue 上で実行されます。
  private func scheduleConnectTimeoutOnConnectionQueue() {
    let seconds = Int(connectTimeoutSeconds)
    scheduleTimeoutOnConnectionQueue(
      seconds: connectTimeoutSeconds, workItem: &connectTimeoutWorkItem
    ) { [weak self] in
      guard let self else { return }
      // connecting 以外なら何もしない
      guard self.connectionState == .connecting else { return }

      // タイムアウト確定のため、状態遷移→リソース解放→UI 更新の順で処理します
      let taskToCancel = self.connectionTask
      self.connectionState = .idle
      self.connectionTask = nil
      self.mediaChannel = nil
      self.updateUIForState()

      // Sora SDK 側の connect 処理をキャンセルします
      taskToCancel?.cancel()

      // 接続失敗のポップアップを表示します
      self.presentAlertMessage(
        title: "接続に失敗しました",
        message: "接続がタイムアウトしました（\(seconds)秒）。"
      )
    }
  }

  // タイムアウト予約をキャンセルします。
  // 古いタイムアウト予約が残ってしまうような場合に関係のないタイムアウトポップアップ表示を防ぎます。
  // connectionQueue 上で実行されます。
  private func cancelConnectTimeoutOnConnectionQueue() {
    cancelTimeoutOnConnectionQueue(workItem: &connectTimeoutWorkItem)
  }

  // quickstart 側の切断タイムアウトをスケジューリングします。
  // connectionQueue 上で実行されます。
  private func scheduleDisconnectTimeoutOnConnectionQueue() {
    scheduleTimeoutOnConnectionQueue(
      seconds: disconnectTimeoutSeconds,
      workItem: &disconnectTimeoutWorkItem
    ) { [weak self] in
      guard let self else { return }
      guard self.connectionState == .disconnecting else { return }

      logger.error("切断タイムアウト: onDisconnect が届かなかったため復旧します")
      let seconds = Int(self.disconnectTimeoutSeconds)

      // onDisconnect が届かないケースに備えて復旧します
      self.connectionTask = nil
      self.mediaChannel = nil
      self.connectionState = .idle
      self.updateUIForState()

      self.presentAlertMessage(
        title: "切断に失敗しました",
        message: "切断がタイムアウトしました（\(seconds)秒）。"
      )
    }
  }

  // 切断タイムアウト予約をキャンセルします。
  // connectionQueue 上で実行されます。
  private func cancelDisconnectTimeoutOnConnectionQueue() {
    cancelTimeoutOnConnectionQueue(workItem: &disconnectTimeoutWorkItem)
  }
}
