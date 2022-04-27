import Sora
import SwiftUI

struct ContentView: View {
    // 接続済みの MediaChannel です。
    @State private var mediaChannel: MediaChannel?

    // 接続試行中にキャンセルするためのオブジェクトです。
    @State private var connectionTask: ConnectionTask?

    @State private var senderStream: MediaStream?
    @State private var senderRendering = true

    // 接続済みであれば true を返します。
    var connecting: Bool {
        mediaChannel?.isAvailable == true
    }

    var body: some View {
        VStack {
            Video(stream: $senderStream, rendering: $senderRendering)

            HStack {
                // ボタンを中央に配置するため、前後にスペースを入れます。
                Spacer()

                Button(action: {
                    connect()
                }, label: {
                    Circle()
                        .foregroundColor(.green)
                        .overlay(
                            Image(systemName: "play.fill")
                                .scaleEffect(2.5)
                                .frame(width: 100, height: 100)
                                .foregroundColor(.white))
                })
                .frame(width: 100, height: 100)

                Spacer()
            }
        }
    }

    /*
     func connect() {
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
     */

    func connect() {
        // 接続試行中のタスクが残っていればキャンセルします。
        connectionTask?.cancel()

        // 接続の設定を行います。
        var config = Configuration(urlCandidates: Environment.urls,
                                   channelId: Environment.channelId,
                                   role: .sendrecv,
                                   multistreamEnabled: true)

        // 接続時に指定したいオプションを以下のように設定します。
        config.signalingConnectMetadata = Environment.signalingConnectMetadata

        /*
         // ストリームが追加されたら受信用の VideoView をストリームにセットします。
         // このアプリでは、複数のユーザーが接続した場合は最後のユーザーの映像のみ描画します。
         let senderStreamId = config.publisherStreamId
         config.mediaChannelHandlers.onAddStream = { stream in
             if stream.streamId != senderStreamId {
                 self.receiverStream = stream
             }
         }
         // 接続先から接続を解除されたときに行う処理です。
         config.mediaChannelHandlers.onDisconnect = { error in
             if let error = error {
                 NSLog(error.localizedDescription)
             }
             self.receiverStream = nil
         }
         */

        // 接続します。
        // connect() の戻り値 ConnectionTask を使うと
        // 接続試行中の状態を強制的に終了させることができます。
        connectionTask = Sora.shared.connect(configuration: config) { mediaChannel, error in
            // 接続に失敗するとエラーが渡されます。
            if let error = error {
                NSLog(error.localizedDescription)
                // TODO: 画面更新
                return
            }

            // 接続に成功した MediaChannel を保持しておきます。
            self.mediaChannel = mediaChannel

            // 接続できたら配信用の VideoView をストリームにセットします。
            if let stream = mediaChannel!.senderStream {
                self.senderStream = stream
                NSLog("set sender stream => \(senderStream), \(self.senderStream)")
                self.senderRendering = false
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
