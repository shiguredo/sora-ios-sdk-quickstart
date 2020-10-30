import UIKit
import Sora

// 接続するサーバーのシグナリング URL
let soraURL = URL(string: "ws://192.168.0.2:5000/signaling")!

// チャネル ID
let soraChannelId = "ios-quickstart"

class ViewController: UIViewController {
    
    @IBOutlet weak var senderVideoView: VideoView!
    @IBOutlet weak var senderMultiplicityControl: UISegmentedControl!
    @IBOutlet weak var senderConnectButton: UIButton!
    
    @IBOutlet weak var receiverVideoView: VideoView!
    @IBOutlet weak var receiverMultiplicityControl: UISegmentedControl!
    @IBOutlet weak var receiverConnectButton: UIButton!
    
    @IBOutlet weak var speakerButton: UIButton!
    @IBOutlet weak var volumeSlider: UISlider!
    
    @IBOutlet weak var audioModeButton: UIBarButtonItem!
    
    var senderMediaChannel: MediaChannel?
    var receiverMediaChannel: MediaChannel?
    var isMuted: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.level = .debug
        
        navigationItem.title = "\(soraChannelId)"
        
        speakerButton.isEnabled = false
        volumeSlider.isEnabled = false
        audioModeButton.isEnabled = false
    }
    
    @IBAction func switchCameraPosition(_ sender: AnyObject) {
        if senderMediaChannel?.isAvailable ?? false {
            // カメラの位置（前面と背面）を切り替えます。
            CameraVideoCapturer.shared.flip()
        }
    }
    
    @IBAction func connectSender(_ sender: AnyObject) {
        if let mediaChannel = senderMediaChannel {
            disconnect(mediaChannel: mediaChannel,
                       multiplicityControl: senderMultiplicityControl,
                       connectButton: senderConnectButton)
            senderMediaChannel = nil
        } else {
            connect(role: .sendonly,
                    multiplicityControl: senderMultiplicityControl,
                    connectButton: senderConnectButton,
                    videoView: senderVideoView)
            { mediaChannel in
                self.senderMediaChannel = mediaChannel
            }
        }
    }
    
    @IBAction func connectReceiver(_ sender: AnyObject) {
        if let mediaChannel = receiverMediaChannel {
            disconnect(mediaChannel: mediaChannel,
                       multiplicityControl: receiverMultiplicityControl,
                       connectButton: receiverConnectButton)
            receiverMediaChannel = nil
        } else {
            connect(role: .recvonly,
                    multiplicityControl: receiverMultiplicityControl,
                    connectButton: receiverConnectButton,
                    videoView: receiverVideoView)
            { mediaChannel in
                self.receiverMediaChannel = mediaChannel
                
                DispatchQueue.main.async {
                    self.speakerButton.isEnabled = true
                    self.volumeSlider.isEnabled = true
                    self.volumeSlider.value = Float(MediaStreamAudioVolume.max)
                    self.audioModeButton.isEnabled = true
                }
            }
        }
    }
    
    @IBAction func muteSpeaker(_ sender: AnyObject) {
        guard receiverMediaChannel != nil else {
            return
        }
        
        isMuted = !isMuted
        receiverMediaChannel!.mainStream?.audioEnabled = !isMuted
        if isMuted {
            DispatchQueue.main.async {
                self.speakerButton.setImage(UIImage(systemName: "speaker.slash.fill"),
                                            for: .normal)
            }
        } else {
            DispatchQueue.main.async {
                self.speakerButton.setImage(UIImage(systemName: "speaker.2.fill"),
                                            
                                            for: .normal)
            }
        }
    }
    
    @IBAction func changeVolume(_ sender: Any) {
        receiverMediaChannel?.mainStream?.remoteAudioVolume = Double(volumeSlider.value)
    }
    
    @IBAction func changeSpeakerMode(_ sender: Any) {
        guard senderMediaChannel != nil || receiverMediaChannel != nil else {
            return
        }
        
        let alert = UIAlertController(title: "音声モードを選択してください", message: nil, preferredStyle: .actionSheet)
        alert.addAction(.init(title: "デフォルト（通話）", style: .default) { _ in
            let _ = Sora.shared.setAudioMode(.default(category: .playAndRecord, output: .default))
        })
        alert.addAction(.init(title: "デフォルト（スピーカー）", style: .default) { _ in
            let _ = Sora.shared.setAudioMode(.default(category: .playAndRecord, output: .speaker))
        })
        alert.addAction(.init(title: "ビデオチャット（通話）", style: .default) { _ in
            let _ = Sora.shared.setAudioMode(.videoChat(output: .default))
        })
        alert.addAction(.init(title: "ビデオチャット（スピーカー）", style: .default) { _ in
            let _ = Sora.shared.setAudioMode(.videoChat(output: .speaker))
        })
        alert.addAction(.init(title: "ボイスチャット（通話）", style: .default) { _ in
            let _ = Sora.shared.setAudioMode(.voiceChat(output: .default))
        })
        alert.addAction(.init(title: "ボイスチャット（スピーカー）", style: .default) { _ in
            let _ = Sora.shared.setAudioMode(.voiceChat(output: .speaker))
        })
        alert.addAction(.init(title: "キャンセル", style: .cancel, handler: nil))
        present(alert, animated: true)
    }
    
    func connect(role: Role,
                 multiplicityControl: UISegmentedControl,
                 connectButton: UIButton,
                 videoView: VideoView,
                 completionHandler: @escaping (MediaChannel?) -> Void) {
        DispatchQueue.main.async {
            connectButton.isEnabled = false
            multiplicityControl.isEnabled = false
            self.audioModeButton.isEnabled = false
        }
        
        // 接続の設定を行います。
        let config = Configuration(url: soraURL,
                                   channelId: soraChannelId,
                                   role: role,
                                   multistreamEnabled: multiplicityControl.selectedSegmentIndex == 1)
        
        // 接続します。
        // connect() の戻り値 ConnectionTask はここでは使いませんが、
        // 接続試行中の状態を強制的に終了させることができます。
        let _ = Sora.shared.connect(configuration: config) { mediaChannel, error in
            // 接続に失敗するとエラーが渡されます。
            if let error = error {
                print(error.localizedDescription)
                DispatchQueue.main.async {
                    connectButton.isEnabled = true
                    multiplicityControl.isEnabled = true
                    self.audioModeButton.isEnabled = false
                }
                completionHandler(nil)
                return
            }
            
            // 接続できたら VideoView をストリームにセットします。
            // マルチストリームの場合、最初に接続したストリームが mainStream です。
            // 受信専用で接続したとき、何も配信されていなければ mainStream は nil です。
            if let stream = mediaChannel!.mainStream {
                stream.videoRenderer = videoView
            }
            
            DispatchQueue.main.async {
                connectButton.isEnabled = true
                connectButton.setImage(UIImage(systemName: "stop.fill"),
                                       for: .normal)
            }
            
            completionHandler(mediaChannel!)
        }
    }
    
    func disconnect(mediaChannel: MediaChannel,
                    multiplicityControl: UISegmentedControl,
                    connectButton: UIButton) {
        if mediaChannel.isAvailable {
            // 接続解除します。
            mediaChannel.disconnect(error: nil)
        }
        
        DispatchQueue.main.async {
            multiplicityControl.isEnabled = true
            connectButton.setImage(UIImage(systemName: "play.fill"),
                                   for: .normal)
            self.audioModeButton.isEnabled = false
        }
    }
    
}

