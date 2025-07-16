import Foundation

enum Environment {
  // 接続するサーバーのシグナリング URL
  static let url = URL(string: "wss://sora.example.com/signaling")!

  // チャネル ID
  static let channelId = "sora"

  // type: connect に含めるメタデータ
  static let signalingConnectMetadata: Encodable? = nil

  // CA 証明書のファイル名 (拡張子なし)
  // PEM ファイルであることを期待します
  static let caCertFilename = ""
}
