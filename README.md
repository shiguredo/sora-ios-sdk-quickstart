# Sora iOS SDK クイックスタート

[![CircleCI](https://circleci.com/gh/shiguredo/sora-ios-sdk-quickstart/tree/develop.svg?style=svg)](https://circleci.com/gh/shiguredo/sora-ios-sdk-quickstart/tree/develop)

このアプリケーションは [Sora iOS SDK](https://github.com/shiguredo/sora-ios-sdk) のサンプルです。

## システム条件

- iOS 10.0 以降 (シミュレーターは非対応)
- Mac OS X 10.12.6 以降
- Xcode 8.3.3 以降
- Swift 3.1
- WebRTC M59
- WebRTC SFU Sora 17.08 以降
- carthage 0.24.0 以降

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

