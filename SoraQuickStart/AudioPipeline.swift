import Foundation
import WebRTC
import Combine

/// 高性能音声処理パイプライン
class HighPerformanceAudioPipeline: NSObject {
    
    // MARK: - キュー定義
    
    /// 音声データ受信用の高優先度キュー
    private let receiveQueue = DispatchQueue(
        label: "audio.receive",
        qos: .userInteractive,
        attributes: .concurrent
    )
    
    /// バッファリング用のキュー
    private let bufferQueue = DispatchQueue(
        label: "audio.buffer",
        qos: .userInitiated
    )
    
    /// 音声処理用のキュー（並列処理可能）
    private let processingQueue = DispatchQueue(
        label: "audio.processing",
        qos: .default,
        attributes: .concurrent,
        target: DispatchQueue.global()
    )
    
    /// API呼び出し用のキュー（レート制限付き）
    private let apiQueue = OperationQueue()
    
    /// ファイル保存用の低優先度キュー
    private let storageQueue = DispatchQueue(
        label: "audio.storage",
        qos: .background
    )
    
    // MARK: - バッファ管理
    
    /// リングバッファ実装
    class RingBuffer {
        private var buffer: UnsafeMutablePointer<UInt8>
        private let capacity: Int
        private var writeIndex = 0
        private var readIndex = 0
        private let lock = NSLock()
        
        init(capacity: Int) {
            self.capacity = capacity
            self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        }
        
        deinit {
            buffer.deallocate()
        }
        
        func write(_ data: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            
            guard availableToWrite >= data.count else { return false }
            
            data.withUnsafeBytes { bytes in
                let bytesPtr = bytes.bindMemory(to: UInt8.self).baseAddress!
                
                if writeIndex + data.count <= capacity {
                    // 連続書き込み
                    buffer.advanced(by: writeIndex)
                        .initialize(from: bytesPtr, count: data.count)
                } else {
                    // ラップアラウンド
                    let firstChunkSize = capacity - writeIndex
                    let secondChunkSize = data.count - firstChunkSize
                    
                    buffer.advanced(by: writeIndex)
                        .initialize(from: bytesPtr, count: firstChunkSize)
                    buffer.initialize(from: bytesPtr.advanced(by: firstChunkSize),
                                    count: secondChunkSize)
                }
            }
            
            writeIndex = (writeIndex + data.count) % capacity
            return true
        }
        
        func read(_ size: Int) -> Data? {
            lock.lock()
            defer { lock.unlock() }
            
            guard availableToRead >= size else { return nil }
            
            var data = Data(count: size)
            data.withUnsafeMutableBytes { bytes in
                let bytesPtr = bytes.bindMemory(to: UInt8.self).baseAddress!
                
                if readIndex + size <= capacity {
                    // 連続読み込み
                    bytesPtr.initialize(
                        from: buffer.advanced(by: readIndex),
                        count: size
                    )
                } else {
                    // ラップアラウンド
                    let firstChunkSize = capacity - readIndex
                    let secondChunkSize = size - firstChunkSize
                    
                    bytesPtr.initialize(
                        from: buffer.advanced(by: readIndex),
                        count: firstChunkSize
                    )
                    bytesPtr.advanced(by: firstChunkSize).initialize(
                        from: buffer,
                        count: secondChunkSize
                    )
                }
            }
            
            readIndex = (readIndex + size) % capacity
            return data
        }
        
        private var availableToRead: Int {
            if writeIndex >= readIndex {
                return writeIndex - readIndex
            } else {
                return capacity - readIndex + writeIndex
            }
        }
        
        private var availableToWrite: Int {
            return capacity - availableToRead - 1
        }
    }
    
    // MARK: - 処理パイプライン
    
    private let audioBuffer: RingBuffer
    private var processingTasks: [UUID: Task<Void, Never>] = [:]
    private let tasksLock = NSLock()
    
    // 設定
    struct Configuration {
        let bufferCapacity: Int = 1024 * 1024 * 2  // 2MB
        let chunkSize: Int = 48000 * 2             // 1秒分のデータ
        let maxConcurrentAPICalls: Int = 3
        let vadThreshold: Double = 1000.0
        let enableRecording: Bool = false
        let enableVAD: Bool = true
        let enableRealtimeTranscription: Bool = true
    }
    
    private let config = Configuration()
    
    // メトリクス
    private var metrics = AudioProcessingMetrics()
    
    struct AudioProcessingMetrics {
        var receivedBytes: Int64 = 0
        var processedBytes: Int64 = 0
        var droppedFrames: Int = 0
        var apiCallCount: Int = 0
        var averageLatency: TimeInterval = 0
        var peakLatency: TimeInterval = 0
    }
    
    // MARK: - 初期化
    
    override init() {
        self.audioBuffer = RingBuffer(capacity: config.bufferCapacity)
        super.init()
        
        // API呼び出しキューの設定
        apiQueue.maxConcurrentOperationCount = config.maxConcurrentAPICalls
        
        // バッファ処理の開始
        startBufferProcessing()
    }
    
    // MARK: - データ受信（最高優先度）
    
    func receiveAudioData(_ data: Data, sampleRate: Int, channels: Int) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        receiveQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // メトリクス更新
            self.metrics.receivedBytes += Int64(data.count)
            
            // リングバッファに書き込み
            if !self.audioBuffer.write(data) {
                // バッファオーバーフロー
                self.metrics.droppedFrames += 1
                self.handleBufferOverflow()
            }
            
            // レイテンシ計測
            let latency = CFAbsoluteTimeGetCurrent() - startTime
            self.updateLatencyMetrics(latency)
        }
    }
    
    // MARK: - バッファ処理層
    
    private func startBufferProcessing() {
        bufferQueue.async { [weak self] in
            while true {
                guard let self = self else { return }
                
                // チャンクサイズ分のデータが溜まるまで待機
                if let audioData = self.audioBuffer.read(self.config.chunkSize) {
                    self.processAudioChunk(audioData)
                } else {
                    // データが足りない場合は少し待機
                    Thread.sleep(forTimeInterval: 0.01) // 10ms
                }
            }
        }
    }
    
    // MARK: - 並列処理層
    
    private func processAudioChunk(_ data: Data) {
        // 各処理を非同期タスクとして起動
        let taskId = UUID()
        
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                // 1. 録音処理
                if config.enableRecording {
                    group.addTask { [weak self] in
                        await self?.recordAudio(data)
                    }
                }
                
                // 2. VAD処理
                if config.enableVAD {
                    group.addTask { [weak self] in
                        await self?.performVAD(data)
                    }
                }
                
                // 3. リアルタイム文字起こし
                if config.enableRealtimeTranscription {
                    group.addTask { [weak self] in
                        await self?.transcribeAudio(data)
                    }
                }
                
                // すべてのタスクの完了を待つ
                await group.waitForAll()
            }
            
            // タスク完了後のクリーンアップ
            self.removeTask(taskId)
        }
        
        // タスク管理
        tasksLock.lock()
        processingTasks[taskId] = task
        tasksLock.unlock()
    }
    
    // MARK: - 個別処理実装
    
    private func recordAudio(_ data: Data) async {
        await withCheckedContinuation { continuation in
            storageQueue.async {
                // ファイル保存処理
                let filename = "audio_\(Date().timeIntervalSince1970).pcm"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(filename)
                
                do {
                    try data.write(to: url)
                } catch {
                    print("Failed to save audio: \(error)")
                }
                
                continuation.resume()
            }
        }
    }
    
    private func performVAD(_ data: Data) async {
        await withCheckedContinuation { continuation in
            processingQueue.async {
                // Voice Activity Detection
                let samples = data.withUnsafeBytes {
                    $0.bindMemory(to: Int16.self)
                }
                
                var energy: Double = 0
                for sample in samples {
                    energy += Double(sample) * Double(sample)
                }
                
                let rms = sqrt(energy / Double(samples.count))
                
                if rms > self.config.vadThreshold {
                    // 音声検出
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .voiceActivityDetected,
                            object: nil,
                            userInfo: ["rms": rms]
                        )
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    private func transcribeAudio(_ data: Data) async {
        // API呼び出しオペレーション
        let operation = BlockOperation {
            // Whisper API呼び出し（実装例）
            Task {
                do {
                    let result = try await self.callWhisperAPI(data)
                    await self.handleTranscriptionResult(result)
                } catch {
                    print("Transcription failed: \(error)")
                }
            }
        }
        
        apiQueue.addOperation(operation)
    }
    
    // MARK: - API呼び出し層
    
    private func callWhisperAPI(_ data: Data) async throws -> String {
        // レート制限とリトライ処理
        return try await withRetry(maxAttempts: 3) {
            // 実際のAPI呼び出し
            // ...
            return "Transcribed text"
        }
    }
    
    private func withRetry<T>(
        maxAttempts: Int,
        delay: TimeInterval = 1.0,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    let backoffDelay = delay * pow(2.0, Double(attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                }
            }
        }
        
        throw lastError!
    }
    
    // MARK: - メトリクスとモニタリング
    
    private func updateLatencyMetrics(_ latency: TimeInterval) {
        metrics.averageLatency = (metrics.averageLatency + latency) / 2
        metrics.peakLatency = max(metrics.peakLatency, latency)
    }
    
    private func handleBufferOverflow() {
        // バッファオーバーフロー時の処理
        // 古いデータを破棄してバッファをクリア
        print("Buffer overflow detected, dropping frames")
        
        // アラート送信
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .audioBufferOverflow,
                object: nil
            )
        }
    }
    
    private func removeTask(_ id: UUID) {
        tasksLock.lock()
        processingTasks.removeValue(forKey: id)
        tasksLock.unlock()
    }
    
    private func handleTranscriptionResult(_ result: String) async {
        // メインスレッドでUI更新
        await MainActor.run {
            NotificationCenter.default.post(
                name: .transcriptionCompleted,
                object: nil,
                userInfo: ["text": result]
            )
        }
    }
    
    // MARK: - パフォーマンスモニタリング
    
    func getMetrics() -> AudioProcessingMetrics {
        return metrics
    }
    
    func resetMetrics() {
        metrics = AudioProcessingMetrics()
    }
    
    // MARK: - クリーンアップ
    
    func shutdown() {
        // すべてのタスクをキャンセル
        tasksLock.lock()
        for (_, task) in processingTasks {
            task.cancel()
        }
        processingTasks.removeAll()
        tasksLock.unlock()
        
        // キューの停止
        apiQueue.cancelAllOperations()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let voiceActivityDetected = Notification.Name("voiceActivityDetected")
    static let audioBufferOverflow = Notification.Name("audioBufferOverflow")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
}

// MARK: - RTCAudioSink実装

extension HighPerformanceAudioPipeline: RTCAudioSink {
    func audioTrack(_ audioTrack: RTCAudioTrack,
                   didReceive audioData: Data,
                   bitsPerSample: Int,
                   sampleRate: Int,
                   numberOfChannels: Int,
                   numberOfFrames: Int) {
        // ⚠️ WebRTCオーディオスレッドから呼ばれる
        // 即座に高速受信キューへ渡してオーディオスレッドを解放
        receiveAudioData(audioData, sampleRate: sampleRate, channels: numberOfChannels)
    }
}
