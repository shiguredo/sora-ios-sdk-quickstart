# Sora iOS SDK クイックスタート

このアプリケーションは [Sora iOS SDK](https://github.com/shiguredo/sora-ios-sdk) のサンプルです。

## About Shiguredo's open source software

We will not respond to PRs or issues that have not been discussed on Discord. Also, Discord is only available in Japanese.

Please read https://github.com/shiguredo/oss before use.

## 時雨堂のオープンソースソフトウェアについて

利用前に https://github.com/shiguredo/oss をお読みください。

## システム条件

- iOS 14 以降
- アーキテクチャ arm64 (シミュレーターの動作は未保証)
- macOS 15.0 以降
- Xcode 26.2
  - Swift 5
- WebRTC SFU Sora 2025.2.0 以降

Xcode と Swift のバージョンによっては、 取得できるバイナリに互換性がない可能性があります。詳しくは[Sora iOS SDK ドキュメント](https://sora-ios-sdk.shiguredo.jp/) を参照してください。

## ビルド

1. クローンします

   ```
   $ git clone https://github.com/shiguredo/sora-ios-sdk-quickstart
   $ cd sora-ios-sdk-quickstart
   ```

2. ``SoraQuickStart/Environment.example.swift`` のファイル名を ``SoraQuickStart/Environment.swift`` に変更し、接続情報を設定します。

   ```
   $ cp SoraQuickStart/Environment.example.swift SoraQuickStart/Environment.swift
   ```

3. ``SoraQuickStart.xcodeproj`` を Xcode で開いてビルドします。

   ```
   $ open SoraQuickStart.xcodeproj
   ```

> [!TIP]
> はじめてビルドを行う場合、 ビルドに失敗し `SwfitLintBuildToolPlugin (SwiftLintPlugin)` に関するプロンプトが表示されたら
> 必ずプラグインを信頼して有効にしてください。そうすることで次回以降ビルドを正常に実行できます。

## ライセンス

このリポジトリに含まれるすべてのアプリアイコン画像（すべての PNG 形式ファイル）のライセンスは [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.ja) です。