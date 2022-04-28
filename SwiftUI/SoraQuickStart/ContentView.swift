import Sora
import SwiftUI

struct ContentView: View {
    // 以下、代入可能なプロパティを @State として定義します。

    // 接続済みの MediaChannel です。
    @State private var mediaChannel: MediaChannel?

    // 接続試行中にキャンセルするためのオブジェクトです。
    @State private var connectionTask: ConnectionTask?

    @ObservedObject private var senderVideoModel = VideoModel()
    @ObservedObject private var receiverVideoModel = VideoModel()

    // 接続時のエラーです。
    @State private var connectionError: Error?

    // アラートを表示する必要がある場合に true にします。
    // エラーが発生したときに使います。
    @State private var showAlert = false

    // 接続済みであれば true を返します。
    var connecting: Bool {
        mediaChannel?.isAvailable == true
    }

    // 画面を構築します。
    var body: some View {
        VStack {
            // 受信映像の上に小さいサイズの配信映像を重ねて表示します。
            ZStack {
                Video(receiverVideoModel)

                VStack {
                    // スペースを上と左にいれて右下に映像ビューを配置します。
                    Spacer()
                    HStack {
                        Spacer()
                        Video(senderVideoModel)
                            .frame(width: 110, height: 170)
                            .border(Color.white, width: 2)
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                    }
                }
            }

            // 接続・切断ボタンを配置します。
            HStack {
                // ボタンを中央に配置するため、前後にスペースを入れます。
                Spacer()

                // 接続・切断ボタンを表示します。
                if !connecting {
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
                } else {
                    Button(action: {
                        disconnect()
                    }, label: {
                        Circle()
                            .foregroundColor(.green)
                            .overlay(
                                Image(systemName: "square.fill")
                                    .scaleEffect(2.5)
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(.white))
                    })
                    .frame(width: 100, height: 100)
                }

                Spacer()
            }
        }

        // 何らかのエラー時にアラートを表示します。
        .alert("エラー", isPresented: $showAlert, actions: {
            Button("OK") {
                showAlert = false
                connectionError = nil
            }
        }, message: {
            if let error = connectionError {
                Text(error.localizedDescription)
            } else {
                Text("エラー内容不明")
            }
        })
    }

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

        // ストリームが追加されたら受信用の VideoView をストリームにセットします。
        // このアプリでは、複数のユーザーが接続した場合は最後のユーザーの映像のみ描画します。
        let senderStreamId = config.publisherStreamId
        config.mediaChannelHandlers.onAddStream = { stream in
            if stream.streamId != senderStreamId {
                self.receiverVideoModel.stream = stream
            }
        }

        // 接続先から接続を解除されたときに行う処理です。
        config.mediaChannelHandlers.onDisconnect = { error in
            if let error = error {
                NSLog(error.localizedDescription)

                // エラーをプロパティにセットします。
                showAlert = true
                connectionError = error
            }
            self.receiverVideoModel.stream = nil
        }

        // 接続します。
        // connect() の戻り値 ConnectionTask を使うと
        // 接続試行中の状態を強制的に終了させることができます。
        connectionTask = Sora.shared.connect(configuration: config) { mediaChannel, error in
            // 接続に失敗するとエラーが渡されます。
            if let error = error {
                NSLog(error.localizedDescription)

                // エラーをプロパティにセットします。
                showAlert = true
                connectionError = error
                return
            }

            // 接続に成功した MediaChannel を保持しておきます。
            self.mediaChannel = mediaChannel

            // 接続できたら配信ストリームを senderStream プロパティにセットします。
            // 配信用の Video ビューは senderStream プロパティを参照しているので、
            // 同プロパティにストリームをセットすると映像が表示されます。
            senderVideoModel.stream = mediaChannel!.senderStream
        }
    }

    func disconnect() {
        // 切断します。
        if mediaChannel?.isAvailable == true {
            mediaChannel?.disconnect(error: nil)
        }
        mediaChannel = nil
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
