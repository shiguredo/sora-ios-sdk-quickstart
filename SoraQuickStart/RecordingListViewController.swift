import UIKit
import AVFoundation

final class RecordingListViewController: UITableViewController {
  weak var audioManager: SoraAudioManager?

  private var recordings: [RecordedAudio] = []
  private var observers: [NSObjectProtocol] = []
  private var player: AVAudioPlayer?
  private var currentlyPlayingURL: URL?

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "録音リスト"
    navigationItem.largeTitleDisplayMode = .never
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "RecordingCell")
    tableView.tableFooterView = UIView()
    tableView.rowHeight = 56

    observers.append(
      NotificationCenter.default.addObserver(
        forName: .audioRecordingSaved,
        object: audioManager,
        queue: .main
      ) { [weak self] _ in
        self?.reloadRecordings()
      }
    )

    observers.append(
      NotificationCenter.default.addObserver(
        forName: .audioRecordingSessionEnded,
        object: audioManager,
        queue: .main
      ) { [weak self] _ in
        self?.reloadRecordings()
      }
    )

    reloadRecordings()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if isMovingFromParent || isBeingDismissed {
      stopPlayback()
    }
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
  }

  // MARK: - Table view data source

  override func numberOfSections(in tableView: UITableView) -> Int {
    1
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    recordings.count
  }

  override func tableView(_ tableView: UITableView,
                          cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "RecordingCell", for: indexPath)
    var content = cell.defaultContentConfiguration()
    let recording = recordings[indexPath.row]
    content.text = recording.url.lastPathComponent

    let dateText = Self.dateFormatter.string(from: recording.startedAt)
    let durationText = formatDuration(recording.duration)
    content.secondaryText = "開始: \(dateText)    長さ: \(durationText)"
    content.secondaryTextProperties.color = .secondaryLabel
    cell.contentConfiguration = content

    if recording.url == currentlyPlayingURL {
      cell.accessoryType = .checkmark
    } else {
      cell.accessoryType = .disclosureIndicator
    }

    return cell
  }

  override func tableView(_ tableView: UITableView,
                          didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let recording = recordings[indexPath.row]
    playRecording(recording)
  }

  // MARK: - Private helpers

  private func reloadRecordings() {
    if let audioManager {
      recordings = audioManager.recordings().sorted { $0.startedAt < $1.startedAt }
    } else {
      recordings = []
    }
    tableView.reloadData()
    updateEmptyState()
  }

  private func updateEmptyState() {
    if recordings.isEmpty {
      let label = UILabel()
      label.text = "録音ファイルがありません"
      label.textColor = .secondaryLabel
      label.numberOfLines = 0
      label.textAlignment = .center
      label.font = UIFont.preferredFont(forTextStyle: .body)
      tableView.backgroundView = label
    } else {
      tableView.backgroundView = nil
    }
  }

  private func playRecording(_ recording: RecordedAudio) {
    stopPlayback()
    do {
      let session = AVAudioSession.sharedInstance()
      print("[kensaku] playback preparing url=\(recording.url.path)")
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true, options: [])
      print("[kensaku] session configured category=\(session.category) mode=\(session.mode)")

      let player = try AVAudioPlayer(contentsOf: recording.url)
      player.delegate = self
      player.prepareToPlay()
      player.play()
      self.player = player
      currentlyPlayingURL = recording.url
      tableView.reloadData()
    } catch {
      print("[kensaku] playback failed url=\(recording.url) error=\(error)")
      currentlyPlayingURL = nil
    }
  }

  private func stopPlayback() {
    player?.stop()
    player = nil
    currentlyPlayingURL = nil
    if isViewLoaded {
      tableView.reloadData()
    }
    let session = AVAudioSession.sharedInstance()
    try? session.setActive(false, options: [.notifyOthersOnDeactivation])
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    guard duration.isFinite && !duration.isNaN else { return "--:--" }
    let totalSeconds = Int(duration.rounded())
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }
}

extension RecordingListViewController: AVAudioPlayerDelegate {
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    currentlyPlayingURL = nil
    tableView.reloadData()
  }
}
