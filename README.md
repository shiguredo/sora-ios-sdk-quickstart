# Sora iOS SDK クイックスタート

[![CircleCI](https://circleci.com/gh/shiguredo/sora-ios-sdk-quickstart/tree/develop.svg?style=svg)](https://circleci.com/gh/shiguredo/sora-ios-sdk-quickstart/tree/develop)

このアプリケーションは [Sora iOS SDK](https://github.com/shiguredo/sora-ios-sdk) のサンプルです。

## システム条件

- iOS 10.0 以降
- アーキテクチャ arm64, armv7 (シミュレーターは非対応)
- Mac OS X 10.12.6 以降
- Xcode 9.0 以降
- Swift 4.0
- Carthage 0.26.2 以降
- WebRTC SFU Sora 18.02 以降


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

