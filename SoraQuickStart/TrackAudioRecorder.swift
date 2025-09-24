import Foundation
import WebRTC

/// Per-track audio recorder that writes PCM data into a playable WAV file.
final class TrackAudioRecorder: NSObject, RTCAudioSink {
  private struct AudioFormat {
    let sampleRate: UInt32
    let channels: UInt16
    let bitsPerSample: UInt16

    var bytesPerFrame: UInt32 {
      UInt32(channels) * UInt32(bitsPerSample) / 8
    }

    var byteRate: UInt32 {
      sampleRate * bytesPerFrame
    }

    var blockAlign: UInt16 {
      channels * (bitsPerSample / 8)
    }
  }

  private let streamId: String
  private let queue: DispatchQueue
  private let recordingsDirectory: URL
  private var format: AudioFormat?
  private var fileHandle: FileHandle?
  private var fileURL: URL?
  private var dataLength: UInt32 = 0
  private var hasFinished = false
  private var startedAt: Date?
  private let onFinish: ((URL, Date, TimeInterval) -> Void)?
  private var hasLoggedFirstPacket = false

  init(streamId: String,
       recordingsDirectory: URL? = nil,
       onFinish: ((URL, Date, TimeInterval) -> Void)? = nil) {
    self.streamId = streamId
    let queueLabel = "audio.recorder." + streamId.replacingOccurrences(of: "[^A-Za-z0-9_.-]",
                                                                        with: "_",
                                                                        options: .regularExpression)
    self.queue = DispatchQueue(label: queueLabel)
    let baseDirectory: URL
    if let explicitDirectory = recordingsDirectory {
      baseDirectory = explicitDirectory
    } else {
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      baseDirectory = documents ?? FileManager.default.temporaryDirectory
    }
    self.recordingsDirectory = baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
    self.onFinish = onFinish
    super.init()
    print("[kensaku] TrackAudioRecorder initialized for stream=\(streamId) directory=\(self.recordingsDirectory.path)")
  }

  deinit {
    print("[kensaku] TrackAudioRecorder deinit stream=\(streamId) hasFinished=\(hasFinished)")
    finishRecording()
  }

  // MARK: - Public API

  /// Returns the current recording file URL if available.
  func currentFileURL() -> URL? {
    queue.sync { fileURL }
  }

  /// Finishes the current recording and finalizes the WAV file.
  func finishRecording() {
    queue.sync {
      guard !hasFinished else { return }
      hasFinished = true

      guard let handle = fileHandle, let format else {
        print("[kensaku] finishRecording skipped: no active file stream=\(streamId)")
        cleanupResources()
        return
      }

      updateHeader(handle: handle, format: format, dataLength: dataLength)
      handle.closeFile()

      defer {
        cleanupResources()
      }

      guard dataLength > 0, let finalURL = fileURL else {
        if let finalURL = fileURL {
          try? FileManager.default.removeItem(at: finalURL)
          print("[kensaku] finishRecording removed empty file stream=\(streamId) path=\(finalURL.path)")
        }
        print("[kensaku] finishRecording no audio data stream=\(streamId)")
        return
      }

      let durationSeconds = Double(dataLength) / Double(format.byteRate)
      let startedAt = self.startedAt ?? Date()
      print("[kensaku] finishRecording completed stream=\(streamId) bytes=\(dataLength) duration=\(String(format: "%.2f", durationSeconds))s path=\(finalURL.path)")
      onFinish?(finalURL, startedAt, durationSeconds)
    }
  }

  // MARK: - RTCAudioSink

  func audioTrack(_ audioTrack: RTCAudioTrack,
                  didReceive audioData: Data,
                  bitsPerSample: Int,
                  sampleRate: Int,
                  numberOfChannels: Int,
                  numberOfFrames: Int) {
    queue.async { [weak self] in
      guard let self else { return }
      do {
        _ = try self.ensureFormat(sampleRate: sampleRate,
                                  channels: numberOfChannels,
                                  bitsPerSample: bitsPerSample)
        self.fileHandle?.write(audioData)
        let increment = UInt32(audioData.count)
        if self.dataLength > UInt32.max - increment {
          self.dataLength = UInt32.max
        } else {
          self.dataLength += increment
        }
        if !self.hasLoggedFirstPacket {
          self.hasLoggedFirstPacket = true
          print("[kensaku] first audio packet stream=\(self.streamId) sampleRate=\(sampleRate) channels=\(numberOfChannels) bitsPerSample=\(bitsPerSample) frames=\(numberOfFrames)")
        }
      } catch {
        print("[kensaku] failed to write audio data stream=\(self.streamId) error=\(error)")
      }
    }
  }

  // MARK: - Helpers

  private func ensureFormat(sampleRate: Int,
                            channels: Int,
                            bitsPerSample: Int) throws -> AudioFormat {
    if let existing = format {
      return existing
    }

    let audioFormat = AudioFormat(sampleRate: UInt32(sampleRate),
                                  channels: UInt16(clamping: channels),
                                  bitsPerSample: UInt16(clamping: bitsPerSample))

    try FileManager.default.createDirectory(at: recordingsDirectory,
                                            withIntermediateDirectories: true)
    let fileURL = makeFileURL()
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    let handle = try FileHandle(forWritingTo: fileURL)
    handle.write(makeHeader(format: audioFormat, dataLength: 0))

    self.fileHandle = handle
    self.fileURL = fileURL
    self.dataLength = 0
    self.format = audioFormat
    self.hasFinished = false
    self.startedAt = Date()
    self.hasLoggedFirstPacket = false
    print("[kensaku] ensureFormat ready stream=\(streamId) sampleRate=\(sampleRate) channels=\(channels) bitsPerSample=\(bitsPerSample) file=\(fileURL.lastPathComponent)")
    return audioFormat
  }

  private func makeFileURL() -> URL {
    let sanitizedStreamId = streamId.replacingOccurrences(of: "[^A-Za-z0-9_.-]",
                                                          with: "_",
                                                          options: .regularExpression)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let timestamp = formatter.string(from: Date())
    let filename = "audio_\(sanitizedStreamId)_\(timestamp).wav"
    return recordingsDirectory.appendingPathComponent(filename, isDirectory: false)
  }

  private func makeHeader(format: AudioFormat, dataLength: UInt32) -> Data {
    var header = Data()
    // RIFF chunk descriptor
    header.append("RIFF".data(using: .ascii)!)
    header.append(uint32LE(36 + dataLength))
    header.append("WAVE".data(using: .ascii)!)

    // fmt sub-chunk
    header.append("fmt ".data(using: .ascii)!)
    header.append(uint32LE(16)) // PCM chunk size
    header.append(uint16LE(1)) // Audio format PCM
    header.append(uint16LE(format.channels))
    header.append(uint32LE(format.sampleRate))
    header.append(uint32LE(format.byteRate))
    header.append(uint16LE(format.blockAlign))
    header.append(uint16LE(format.bitsPerSample))

    // data sub-chunk
    header.append("data".data(using: .ascii)!)
    header.append(uint32LE(dataLength))
    return header
  }

  private func updateHeader(handle: FileHandle,
                            format: AudioFormat,
                            dataLength: UInt32) {
    let totalSize = 36 + dataLength
    handle.seek(toFileOffset: 4)
    handle.write(uint32LE(totalSize))
    handle.seek(toFileOffset: 40)
    handle.write(uint32LE(dataLength))
  }

  private func cleanupResources() {
    fileHandle = nil
    format = nil
    dataLength = 0
    fileURL = nil
    startedAt = nil
  }

  private func uint16LE(_ value: UInt16) -> Data {
    var littleEndian = value.littleEndian
    return Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size)
  }

  private func uint32LE(_ value: UInt32) -> Data {
    var littleEndian = value.littleEndian
    return Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size)
  }
}
