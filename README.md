# Sora iOS SDK クイックスタート

[![CircleCI](https://circleci.com/gh/shiguredo/sora-ios-sdk-quickstart/tree/develop.svg?style=svg)](https://circleci.com/gh/shiguredo/sora-ios-sdk-quickstart/tree/develop)

このアプリケーションは [Sora iOS SDK](https://github.com/shiguredo/sora-ios-sdk) のサンプルです。

## システム条件

- iOS 10.0 以降
- アーキテクチャ arm64, x86_64 (シミュレーターの動作は未保証)
- macOS 10.15 以降
- Xcode 11.1
- Swift 5.1
- Carthage 0.33.0 以降、または CocoaPods 1.6.1 以降
- WebRTC SFU Sora 19.04.0 以降

Xcode と Swift のバージョンによっては、 Carthage と CocoaPods で取得できるバイナリに互換性がない可能性があります。詳しくはドキュメントを参照してください。

## ビルド

1. クローンし、 Carthage でライブラリを取得します。

   ```
   $ git clone https://github.com/shiguredo/sora-ios-sdk-quickstart
   $ cd sora-ios-sdk-quickstart
   $ carthage update --platform iOS
   ```

2. ``SoraQuickStart.xcodeproj`` を Xcode で開いてビルドします。

## 注意

Carthage のパスは ``/usr/local/bin/carthage`` を前提としています。
他のパスにインストールされている場合は Xcode プロジェクトのビルドフェーズを変更するか、シンボリックリンクをはってください。

