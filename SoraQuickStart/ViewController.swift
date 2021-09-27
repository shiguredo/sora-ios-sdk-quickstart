import UIKit
import Sora

// 接続するサーバーのシグナリング URL
let soraURL = URL(string: "wss://sora.example.com/signaling")!

// チャネル ID
let soraChannelId = "sora"

class ViewController: UIViewController {
    
    @IBOutlet weak var senderVideoView: VideoView!
    @IBOutlet weak var receiverVideoView: VideoView!
    @IBOutlet weak var connectImageView: UIImageView!
    //
    var camera: CameraVideoCapturer?
    var isFront = true

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
        
        navigationItem.title = "\(soraChannelId)"
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
                if CameraVideoCapturer.front.isRunning {
                    CameraVideoCapturer.front.stop() { error in
                        if let error = error {
                            NSLog(error.localizedDescription)
                        }
                    }
                }
                if CameraVideoCapturer.back.isRunning {
                    CameraVideoCapturer.back.stop { error in
                        if let error = error {
                            NSLog(error.localizedDescription)
                        }
                    }
                }
            }
            updateUI(false)
        } else {
            // 未接続なら接続します。
            connect()
            updateUI(true)
        }
    }

    func connect() {
        // 接続の設定を行います。
        var config = Configuration(url: soraURL,
                                   channelId: soraChannelId,
                                   role: .sendrecv,
                                   multistreamEnabled: true)
        
        // ストリームが追加されたら受信用の VideoView をストリームにセットします。
        // このアプリでは、複数のユーザーが接続した場合は最後のユーザーの映像のみ描画します。
        config.mediaChannelHandlers.onAddStream = {stream in
            if stream.streamId != config.publisherStreamId {
                stream.videoRenderer = self.receiverVideoView
            }
        }
        // 接続先から接続を解除されたときに行う処理です。
        config.mediaChannelHandlers.onDisconnect = { error in
            if let error = error {
                NSLog(error.localizedDescription)
            }
            self.updateUI(false)
        }

        // カメラを起動しない
        config.cameraSettings = CameraSettings(isEnabled: false)

//        let frontCameraHandlers = CameraVideoCapturerHandlers()
//        frontCameraHandlers.onCapture = {
//            frame in
//            //NSLog("front camera onCapture")
//            return frame
//        }
//        frontCameraHandlers.onStart = {
//            NSLog("front camera onStart")
//        }
//        frontCameraHandlers.onStop = {
//            NSLog("front camera onStop")
//        }
//
//        let backCameraHandlers = CameraVideoCapturerHandlers()
//        backCameraHandlers.onCapture = {
//            frame in
//            //NSLog("back camera onCapture")
//            return frame
//        }
//        backCameraHandlers.onStart = {
//            NSLog("back camera onStart")
//        }
//        backCameraHandlers.onStop = {
//            NSLog("back camera onStop")
//        }
//
//        CameraVideoCapturer.front.handlers = frontCameraHandlers
//        CameraVideoCapturer.back.handlers = backCameraHandlers

        CameraVideoCapturer.handlers.onStart = { capturer in
            // カメラ位置ごとの処理
            switch capturer.position {
            case .front:
                // 前面カメラ時
                NSLog("# front camera start")
            case .back:
                // 背面カメラ時
                NSLog("# back camera start")
            default:
                break
            }
            // カメラ位置に依存しない処理
            NSLog("# capturer start => \(capturer)")
        }

        CameraVideoCapturer.handlers.onStop = { capturer in
            // カメラ位置ごとの処理
            switch capturer.position {
            case .front:
                // 前面カメラ時
                NSLog("# front camera stop")
            case .back:
                // 背面カメラ時
                NSLog("# back camera stop")
            default:
                break
            }
            // カメラ位置に依存しない処理
            NSLog("# capturer stop => \(capturer)")
        }

        CameraVideoCapturer.handlers.onCapture = { capturer, frame in
            // カメラ位置ごとの処理
            switch capturer.position {
            case .front:
                // 前面カメラ時
                NSLog("# front camera capture")
            case .back:
                // 背面カメラ時
                NSLog("# back camera capture")
            default:
                break
            }
            // カメラ位置に依存しない処理
            NSLog("# capturer capture => \(capturer), frame => \(frame)")
            return frame
        }

        // 接続します。
        // connect() の戻り値 ConnectionTask を使うと
        // 接続試行中の状態を強制的に終了させることができます。
        connectionTask = Sora.shared.connect(configuration: config) { mediaChannel, error in
            // 接続に失敗するとエラーが渡されます。
            if let error = error {
                NSLog(error.localizedDescription)
                self.updateUI(false)
                return
            }

            // 接続に成功した MediaChannel を保持しておきます。
            self.mediaChannel = mediaChannel

            
            // 接続できたら配信用の VideoView をストリームにセットします。
//            if let stream = mediaChannel!.senderStream {
//                stream.videoRenderer = self.senderVideoView
//            }
        }
    }

    
    @IBAction func start(_ sender: Any) {
        guard let stream = mediaChannel!.senderStream else {
            return
        }
        stream.videoRenderer = self.senderVideoView
        let vga = CameraSettings.Resolution.vga480p
        self.camera = isFront ? CameraVideoCapturer.front : CameraVideoCapturer.back
        let format = CameraVideoCapturer.format(width: vga.width, height: vga.height, for: self.camera!.device!)
        self.camera!.start(format: format!, frameRate: 30) { error in
            if let error = error {
                NSLog(error.localizedDescription)
                return
            }
            CameraVideoCapturer.current!.stream = stream
        }
    }
    
    @IBAction func stop(_ sender: Any) {
        CameraVideoCapturer.current?.stop() { error in
            if let error = error {
                NSLog(error.localizedDescription)
            }
        }
    }
    
    @IBAction func flip(_ sender: Any) {
        CameraVideoCapturer.flip(CameraVideoCapturer.current!) { error in
            if let error = error {
                NSLog(error.localizedDescription)
                return
            }
            self.isFront = self.isFront ? false : true
        }
        NSLog("flip camera")
    }
    
    @IBAction func restart(_ sender: Any) {
        if self.isFront == true{
            CameraVideoCapturer.front.restart() { error in
                if let error = error {
                    NSLog(error.localizedDescription)
                }
            }
            NSLog("restart front camera")
        } else {
            CameraVideoCapturer.back.restart() { error in
                if let error = error {
                    NSLog(error.localizedDescription)
                }
            }
            NSLog("restart back camera")
        }
    }
    
    @IBAction func change(_ sender: Any) {
        let hd = CameraSettings.Resolution.hd1080p
        let format = CameraVideoCapturer.format(width: hd.width, height: hd.height, for: CameraVideoCapturer.current!.device!)
        CameraVideoCapturer.current?.change(format: format, frameRate: 1) { error in
            if let error = error {
                NSLog(error.localizedDescription)
                return
            }
        }
        NSLog("change camera")
    }
}

