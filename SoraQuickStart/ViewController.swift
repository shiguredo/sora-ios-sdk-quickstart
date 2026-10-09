import Sora
import UIKit
import os

private let logger = Logger(
  subsystem: "jp.shiguredo.sora-ios-sdk-quickstart",
  category: "ViewController"
)

// 接続状態の管理用 Enum です。
private enum ConnectionState {
  case idle
  case connecting
  case connected
  case disconnecting
}

// 接続結果の管理用 Enum です。
private enum ConnectResult: Sendable {
  // 接続成功です。MediaChannel は Sendable ではないため購読 API では配送されません。
  // connectionId から Sora の管理対象を引きます。
  case connected(connectionId: String)
  // 接続失敗です。
  case failed(message: String)
}

// 接続処理の状態と直列化を所有する controller です。
//
// @MainActor 隔離の ViewController に状態を置くと main actor 隔離になり、自身の queue 上の処理から
// 触れられなくなるため、状態と queue をこの型へ閉じます。可変状態へのアクセスはこの queue 上だけで
// 行うため @unchecked Sendable とします。
// 保持する MediaChannel / ConnectionTask は Sendable ではないが、SDK 側の可変状態は内部の lock で
// 排他されており (MediaChannel.streams は transportStorage、MediaStream.videoRenderer は
// getter / setter の lock、ConnectionTask の状態は stateLock)、この queue 上から扱っても
// データ競合しない。
private final class ConnectionController: @unchecked Sendable {
  let queue = DispatchQueue(
    label: "jp.shiguredo.sora-ios-sdk-quickstart.connectionQueue")

  var state: ConnectionState = .idle
  var mediaChannel: MediaChannel?
  var connectTimeoutWorkItem: DispatchWorkItem?
  var disconnectTimeoutWorkItem: DispatchWorkItem?
  var connectionTask: ConnectionTask?
}

@MainActor
class ViewController: UIViewController {
  @IBOutlet weak var senderVideoView: VideoView!
  @IBOutlet weak var receiverVideoView: VideoView!
  @IBOutlet weak var connectImageView: UIImageView!
  // 接続/切断処理中はタップを無効化するための Gesture Recognizer (タッチ処理制御)です
  @IBOutlet private weak var connectTapGestureRecognizer: UITapGestureRecognizer?

  // MARK: - 接続処理の状態

  // 接続処理の状態と直列化は ConnectionController が所有します。ConnectionController の
  // 可変状態には connection.queue 上だけでアクセスします。
  private let connection = ConnectionController()

  // quickstart 側での Sora 接続試行のタイムアウト (秒) です
  private let connectTimeoutSeconds: TimeInterval = 15
  // quickstart 側での Sora 切断待ちのタイムアウト (秒) です
  private let disconnectTimeoutSeconds: TimeInterval = 10

  // MARK: - main actor が所有する状態

  // 受信映像を描画している MediaStream です (描画対象の追跡と、描画を止めるために保持します)。
  private var displayedReceiverStream: MediaStream?
  // MediaChannel のイベント購読タスクです。接続ごとに作り直します。
  private var mediaChannelEventTask: Task<Void, Never>?

  // MARK: - ライフサイクル

  override func viewDidLoad() {
    super.viewDidLoad()
    Logger.shared.level = .debug
    Sora.setWebRTCLogLevel(.info)

    navigationItem.title = "\(Environment.channelId)"
    // 接続処理の状態は ConnectionController が所有するため、初期表示は .idle を直接指定します。
    updateUIForState(.idle)

    // 接続結果 (connected / connectFailed) は購読 API で受けるため、接続を開始する前に
    // 購読を開始します。購読を開始する前に配送されたイベントは届きません。
    startSoraEventSubscription()
  }

  // MARK: - イベントの購読 (main actor 上で実行)

  // Sora のイベント購読を開始します。
  // イベントの payload は Sendable な値のため main actor で受け、状態の更新は
  // connection.queue へ渡して直列化します。
  private func startSoraEventSubscription() {
    let events = Sora.shared.subscribeEvents()
    Task { [weak self] in
      for await event in events {
        guard let self else { return }
        switch event.kind {
        case .mediaChannelAdded:
          // MediaChannel は接続の完了前に追加されるため、ここで購読を開始します。
          // 接続の完了前に配送される .streamAdded を取り逃した場合は、接続完了時の
          // 受信ストリームの再スキャンで拾います。
          self.startMediaChannelEventSubscription()
        case .connected:
          // SDK の契約では .connected は必ず接続 ID を持つため、欠落は接続失敗として扱います
          self.dispatchConnectResult(
            event.connectionId.map { ConnectResult.connected(connectionId: $0) }
              ?? .failed(message: "接続 ID を取得できません"))
        case .connectFailed:
          // SDK の契約では .connectFailed は必ずエラーを持つため、欠落は防御的に処理します
          self.dispatchConnectResult(
            .failed(message: event.error?.message ?? "不明なエラー"))
        default:
          break
        }
      }
    }
  }

  // MediaChannel のイベント購読を開始します。
  private func startMediaChannelEventSubscription() {
    // 接続を試行中の MediaChannel は、接続ごとに Sora の管理対象の末尾へ追加されるという
    // SDK の実装に依存して特定します (イベントは接続 ID を持たないため、接続の完了前に
    // 参照を取得するにはこれを使います)。
    guard let mediaChannel = Sora.shared.mediaChannels.last else { return }

    // 購読を開始してから Task で受信します (購読を開始する前に配送されたイベントは届きません)。
    let events = mediaChannel.subscribeEvents()
    // 前の接続の購読が残っている場合は終了します (通常は切断で MediaChannel 側から終端します)。
    mediaChannelEventTask?.cancel()
    mediaChannelEventTask = Task { [weak self] in
      for await event in events {
        guard let self else { return }
        switch event.kind {
        case .streamAdded:
          self.handleStreamAdded(mediaChannel, streamId: event.streamId)
        case .streamRemoved:
          self.handleStreamRemoved(mediaChannel, streamId: event.streamId)
        case .signalingReceivedJSON:
          logger.debug("シグナリング受信: \(event.signalingJSON ?? "", privacy: .public)")
        case .disconnected:
          // 切断時は描画対象を手放します (描画の停止はストリームの終了で行われます)。
          self.detachReceiverVideoView()
          self.connection.queue.async { [weak self] in
            guard let self else { return }
            self.handleDisconnectOnConnectionQueue(closeEvent: event.closeEvent)
          }
        default:
          break
        }
      }
    }
  }

  // 接続結果を connection.queue へ渡します。
  private func dispatchConnectResult(_ result: ConnectResult) {
    connection.queue.async { [weak self] in
      guard let self else { return }
      self.handleConnectResultOnConnectionQueue(result)
    }
  }

  // MARK: - 受信映像の描画 (main actor 上で実行)

  // .streamAdded を処理します。
  private func handleStreamAdded(_ mediaChannel: MediaChannel, streamId: String?) {
    guard let streamId else { return }
    // 送信ストリーム (自分の映像) は受信用 VideoView の対象外です。
    guard streamId != mediaChannel.configuration.publisherStreamId else { return }

    // イベントはストリーム ID だけを運ぶため、MediaChannel.streams から実体を解決します。
    guard let stream = mediaChannel.streams.first(where: { $0.streamId == streamId }) else {
      return
    }

    attachReceiverVideoView(to: stream)
  }

  // .streamRemoved を処理します。
  // ストリームの削除では renderer の callback は配送されないため、描画を止めるかは
  // アプリ側で判断します。
  private func handleStreamRemoved(_ mediaChannel: MediaChannel, streamId: String?) {
    // 削除されたストリームは既に MediaChannel.streams に無いため、保持している参照で判定します。
    guard let streamId, displayedReceiverStream?.streamId == streamId else { return }

    // 表示対象が削除された場合は、残っている受信ストリームへ描画対象を移します
    // (残っている限り描画は止めません)。
    if let stream = mediaChannel.receiverStreams.last {
      attachReceiverVideoView(to: stream)
      return
    }

    detachReceiverVideoView()
  }

  // 受信ストリームを VideoView に描画します。
  private func attachReceiverVideoView(to stream: MediaStream) {
    // 複数の受信ストリームがある場合は同じ VideoView を共有するため、最後に設定した
    // ストリームを描画対象として追跡します (表示される frame は各ストリームの到着順です)。
    displayedReceiverStream = stream
    stream.videoRenderer = receiverVideoView
  }

  // 受信映像の描画を止めます。
  private func detachReceiverVideoView() {
    displayedReceiverStream?.videoRenderer = nil
    displayedReceiverStream = nil
  }

  // MARK: - UI

  // 接続ボタンの UI を更新します。
  // connection.queue 上からも呼ぶため nonisolated にし、UI 操作は main actor へ束ねます
  // (presentAlertMessage も同じ理由で nonisolated にしています)。
  nonisolated private func updateUIForState(_ state: ConnectionState) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let isInteractive = state == .idle || state == .connected
      self.connectTapGestureRecognizer?.isEnabled = isInteractive

      if state == .idle {
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
  nonisolated private func presentAlertMessage(title: String, message: String) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let alertController = UIAlertController(
        title: title,
        message: message,
        preferredStyle: .alert)
      alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
      self.present(alertController, animated: true, completion: nil)
    }
  }

  // 接続処理の状態機械の入口です。
  // 接続と切断の連打を connection.queue で直列化して順次処理します。
  @IBAction func connect(_ sender: AnyObject) {
    connection.queue.async { [weak self] in
      guard let self else { return }
      switch connection.state {
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

  // MARK: - 接続処理 (connection.queue 上で実行)

  // このセクションのメソッドは connection.queue 上で実行するため nonisolated にしています。
  // @MainActor 隔離のまま connection.queue から呼び出すと、メソッド内のクロージャリテラルが
  // main actor 隔離を継承し、connection.queue 上での実行時に隔離チェックでトラップします
  // (SDK ドキュメントの「コールバックを Swift 6 で扱う」と同じ理由です)。

  // Sora 接続を行います。
  nonisolated private func startConnectOnConnectionQueue() {
    guard connection.state == .idle else {
      return
    }

    connection.state = .connecting
    updateUIForState(connection.state)
    scheduleConnectTimeoutOnConnectionQueue()

    // 接続の設定を行います。
    var config = Configuration(
      url: Environment.url,
      channelId: Environment.channelId,
      role: .sendrecv)

    // 接続時に指定したいオプションを以下のように設定します。
    config.signalingConnectMetadata = Environment.signalingConnectMetadata

    // 接続の結果は購読 API の .connected / .connectFailed で受けるため、handler は使いません。
    // @Sendable を付け、任意のスレッドから呼ばれる handler であることを示します。
    connection.connectionTask = Sora.shared.connect(configuration: config) { @Sendable _, _ in }
  }

  // 接続結果を処理します。
  nonisolated private func handleConnectResultOnConnectionQueue(_ result: ConnectResult) {
    // タイムアウトで .idle に戻った後、遅れて接続が成功した場合は採用せず切断します。
    guard connection.state == .connecting else {
      if case .connected(let connectionId) = result,
        let mediaChannel = mediaChannelForConnectionId(connectionId)
      {
        mediaChannel.disconnect(error: nil)
      }
      return
    }

    cancelConnectTimeoutOnConnectionQueue()
    connection.connectionTask = nil

    switch result {
    case .failed(let message):
      logger.error("接続失敗: \(message)")
      presentAlertMessage(title: "接続に失敗しました", message: message)
      connection.state = .idle
      updateUIForState(connection.state)
      detachReceiverVideoViewOnMainActor()
    case .connected(let connectionId):
      guard let mediaChannel = mediaChannelForConnectionId(connectionId) else {
        // 接続は確立していますが、接続を操作できないため状態を戻します
        logger.error("MediaChannel を取得できません: connectionId=\(connectionId, privacy: .public)")
        connection.state = .idle
        updateUIForState(connection.state)
        detachReceiverVideoViewOnMainActor()
        return
      }

      connection.mediaChannel = mediaChannel
      connection.state = .connected
      updateUIForState(connection.state)

      attachVideoRenderers(mediaChannel)
    }
  }

  // 接続 ID に対応する MediaChannel を Sora の管理対象から取得します。
  nonisolated private func mediaChannelForConnectionId(_ connectionId: String) -> MediaChannel? {
    Sora.shared.mediaChannels.first { $0.connectionId == connectionId }
  }

  // 送信映像と受信映像の描画先を設定します。
  // 接続の完了前に配送された .streamAdded を取り逃した場合に備えて、現在の受信ストリームも
  // 対象にします (同じ VideoView の再設定では何も起きないため、冪等です)。
  nonisolated private func attachVideoRenderers(_ mediaChannel: MediaChannel) {
    // MediaStream は Sendable ではないため、nonisolated(unsafe) を付けて main actor へ渡します
    // (SDK ドキュメントのパターン)。
    if let stream = mediaChannel.senderStream {
      nonisolated(unsafe) let senderStream = stream
      Task { @MainActor [weak self] in
        guard let self else { return }
        senderStream.videoRenderer = self.senderVideoView
      }
    }

    // MediaChannel は Sendable ではないため、nonisolated(unsafe) を付けて main actor へ渡します。
    nonisolated(unsafe) let channel = mediaChannel
    Task { @MainActor [weak self] in
      guard let self else { return }
      // 受信ストリームは main actor で読み直します (削除済みのストリームを設定しないため)。
      for stream in channel.receiverStreams {
        self.attachReceiverVideoView(to: stream)
      }
    }
  }

  // 接続の切断を処理します。
  nonisolated private func handleDisconnectOnConnectionQueue(closeEvent: SoraCloseEvent?) {
    // 後片付け済み (.idle) の状態で遅れて届いた .disconnected は無視します
    guard connection.state != .idle else { return }

    cancelConnectTimeoutOnConnectionQueue()
    cancelDisconnectTimeoutOnConnectionQueue()

    if let closeEvent {
      switch closeEvent {
      case .ok(let code, let reason):
        logger.info("接続解除: ステータスコード: \(code), 理由: \(reason)")
      case .error(let error):
        let message = error.localizedDescription
        logger.error("接続エラー: \(message)")
        presentAlertMessage(title: "接続エラーが発生しました", message: message)
      }
    }

    connection.connectionTask = nil
    connection.mediaChannel = nil
    connection.state = .idle
    updateUIForState(connection.state)
  }

  // Sora 切断処理を行います。
  nonisolated private func startDisconnectOnConnectionQueue() {
    guard connection.state == .connected else {
      return
    }

    guard let mediaChannel = connection.mediaChannel else {
      // 状態と実体がズレている場合は復旧させます
      connection.state = .idle
      updateUIForState(connection.state)
      return
    }

    connection.state = .disconnecting
    updateUIForState(connection.state)
    cancelConnectTimeoutOnConnectionQueue()
    scheduleDisconnectTimeoutOnConnectionQueue()

    // MediaChannel の破棄は .disconnected 側で一元的に行います。
    mediaChannel.disconnect(error: nil)
  }

  // 描画中の受信ストリームを手放します。
  // connection.queue 上から呼ぶため nonisolated にし、後始末は main actor へ束ねます。
  nonisolated private func detachReceiverVideoViewOnMainActor() {
    Task { @MainActor [weak self] in
      self?.detachReceiverVideoView()
    }
  }

  // quickstart 側の接続タイムアウトをスケジューリングします。
  nonisolated private func scheduleConnectTimeoutOnConnectionQueue() {
    let seconds = Int(connectTimeoutSeconds)
    scheduleTimeoutOnConnectionQueue(
      seconds: connectTimeoutSeconds, workItem: &connection.connectTimeoutWorkItem
    ) { [weak self] in
      guard let self else { return }
      // タイムアウト発火までに状態が変わっている (接続済み等) 場合は何もしません
      guard connection.state == .connecting else { return }

      // 遅れて届く .connected / .connectFailed を今回の接続として扱わないよう、先に .idle へ戻します
      let taskToCancel = connection.connectionTask
      connection.state = .idle
      connection.connectionTask = nil
      connection.mediaChannel = nil
      self.updateUIForState(connection.state)
      self.detachReceiverVideoViewOnMainActor()

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
  nonisolated private func cancelConnectTimeoutOnConnectionQueue() {
    cancelTimeoutOnConnectionQueue(workItem: &connection.connectTimeoutWorkItem)
  }

  // quickstart 側の切断タイムアウトをスケジューリングします。
  nonisolated private func scheduleDisconnectTimeoutOnConnectionQueue() {
    scheduleTimeoutOnConnectionQueue(
      seconds: disconnectTimeoutSeconds,
      workItem: &connection.disconnectTimeoutWorkItem
    ) { [weak self] in
      guard let self else { return }
      guard connection.state == .disconnecting else { return }

      logger.error("切断タイムアウト: .disconnected が届かなかったため復旧します")
      let seconds = Int(self.disconnectTimeoutSeconds)

      // .disconnected が届かないケースに備えて復旧します
      connection.mediaChannel = nil
      connection.state = .idle
      self.updateUIForState(connection.state)
      self.detachReceiverVideoViewOnMainActor()

      self.presentAlertMessage(
        title: "切断に失敗しました",
        message: "切断がタイムアウトしました（\(seconds)秒）。"
      )
    }
  }

  // 切断タイムアウト予約をキャンセルします。
  nonisolated private func cancelDisconnectTimeoutOnConnectionQueue() {
    cancelTimeoutOnConnectionQueue(workItem: &connection.disconnectTimeoutWorkItem)
  }

  // connection.queue 上でのみ呼び出す前提の汎用タイムアウト処理です。
  nonisolated private func scheduleTimeoutOnConnectionQueue(
    seconds: TimeInterval,
    workItem: inout DispatchWorkItem?,
    action: @escaping () -> Void
  ) {
    cancelTimeoutOnConnectionQueue(workItem: &workItem)
    let item = DispatchWorkItem(block: action)
    workItem = item
    connection.queue.asyncAfter(deadline: .now() + seconds, execute: item)
  }

  // connection.queue 上でのみ呼び出す前提の汎用タイムアウトキャンセル処理です。
  nonisolated private func cancelTimeoutOnConnectionQueue(workItem: inout DispatchWorkItem?) {
    workItem?.cancel()
    workItem = nil
  }
}
