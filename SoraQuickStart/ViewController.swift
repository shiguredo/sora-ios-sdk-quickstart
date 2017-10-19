import UIKit
import Sora

let SoraServerURL = "ws://192.168.0.2:5000/signaling"
let SoraServerMediaChannelId = "ios-quickstart"

class ViewController: UIViewController {

    @IBOutlet weak var publisherVideoView: VideoView!
    @IBOutlet weak var subscriberVideoView: VideoView!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    
    var publisher: MediaChannel!
    var subscriber: MediaChannel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        connectButton.isEnabled = true
        disconnectButton.isEnabled = false
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func connect(_ sender: AnyObject) {
        connectButton.isEnabled = false
        disconnectButton.isEnabled = false
        
        let url = URL(string: SoraServerURL)!
        let pubConfig = Configuration(url: url,
                                      channelId: SoraServerMediaChannelId,
                                      role: .publisher)
        Sora.shared.connect(configuration: pubConfig) { pub, error in
            if let error = error {
                print(error.localizedDescription)
                self.connectButton.isEnabled = true
                return
            }
            
            let subConfig = Configuration(url: url,
                                          channelId: SoraServerMediaChannelId,
                                          role: .subscriber)
            Sora.shared.connect(configuration: subConfig) {
                sub, error in
                if let error = error {
                    print(error.localizedDescription)
                    self.connectButton.isEnabled = true
                    return
                }
                self.disconnectButton.isEnabled = true
                
                self.publisher = pub
                self.publisher.mainStream!.videoRenderer = self.publisherVideoView
                self.subscriber = sub
                self.subscriber.mainStream!.videoRenderer = self.subscriberVideoView
            }
        }
    }
    
    @IBAction func disconnect(_ sender: AnyObject) {
        publisher.disconnect(error: nil)
        subscriber.disconnect(error: nil)
        self.connectButton.isEnabled = true
        self.disconnectButton.isEnabled = false
    }
    
    @IBAction func switchCameraPosition(_ sender: AnyObject) {
        if disconnectButton.isEnabled {
            CameraVideoCapturer.shared.flip()
        }
    }
    
}

