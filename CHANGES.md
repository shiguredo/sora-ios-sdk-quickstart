# 変更履歴

- CHANGE
  - 下位互換のない変更
- UPDATE
  - 下位互換がある変更
- ADD
  - 下位互換がある追加
- FIX
  - バグ修正

## develop

- [UPDATE] Github Actions を actions/cache@v4 にあげる
  - @miosakuma
- [UPDATE] Github Actions を macos-14  にあげる
  - @miosakuma
- [UPDATE] Github Actions を Xcode 15.2, iphoneos17.2 にあげる
  - @miosakuma

## sora-ios-sdk-2024.1.0

- [UPDATE] システム条件を変更する
  - macOS 14.3.1 以降
  - WebRTC SFU Sora 2023.2.0 以降
  - Xcode 15.2
  - Swift 5.9.2
  - CocoaPods 1.15.2 以降
  - @miosakuma

## sora-ios-sdk-2023.3.1

- [UPDATE] Sora iOS SDK を 2023.3.1 にあげる
  - @miosakuma

## sora-ios-sdk-2023.3.0

- [UPDATE] SwiftLint, SwiftFormat/CLI を一時的にコメントアウトする
  - SwiftLint, SwiftFormat/CLI が Swift Swift 5.9 に対応できていないため
  - 対応が完了したら戻す
  - @miosakuma

## sora-ios-sdk-2023.2.0

- [UPDATE] システム条件を変更する
  - macOS 13.4.1 以降
  - Xcode 14.3.1
  - Swift 5.8.1
  - CocoaPods 1.12.1 以降
  - WebRTC SFU Sora 2023.1.0 以降
  - @miosakuma

## sora-ios-sdk-2023.1.0

- [UPDATE] システム条件を変更する
  - macOS 13.3 以降
  - Xcode 14.3
  - Swift 5.8
  - CocoaPods 1.12.0 以降
  - WebRTC SFU Sora 2022.2.0 以降
  - @miosakuma

## sora-ios-sdk-2022.6.0

- [CHANGE] システム条件を変更する
  - アーキテクチャ から x86_64 を削除
  - macOS 12.6 以降
  - Xcode 14.0
  - Swift 5.7
  - CocoaPods 1.11.3 以降
  - @miosakuma

## sora-ios-sdk-2022.5.0

- [UPDATE] システム条件を変更する
  - macOS 12.3 以降
  - Xcode 13.4.1
  - @miosakuma

## sora-ios-sdk-2022.4.0

- [UPDATE] システム条件を変更する
  - macOS 12.3 以降
  - WebRTC SFU Sora 2022.1 以降
  - @miosakuma

## sora-ios-sdk-2022.3.0

- [ADD] 接続失敗時とサーバーによる切断時にエラー内容をアラートで表示する
  - @szktty

## sora-ios-sdk-2022.2.0

- [UPDATE] Environment.example.swift に signalingConnectMetadata を追加する
  - @miosakuma
