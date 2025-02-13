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

### misc

- [CHANGE] フォーマッターを SwiftFormat から swift-format に変更する
  - SwiftFormat のための設定ファイルである .swiftformat と .swift-version を削除
  - フォーマット設定はデフォルトを採用したため、.swift-format は利用しない
  - @zztkm
- [UPDATE] リンターの実行をシェルスクリプトではなく、Xcode の Build Phases に設定する
  - @zztkm
- [UPDATE] 依存管理を CocoaPods から Xcode の Swift Package Manager に移行する
  - Sora iOS SDK と SwiftLint を Swift Package Manager 管理に移行
  - Podfile を削除
  - 不要な buildPhases を削除
    - SwfitFormat と SwiftLint を自動実行するためのものだったが利用していないため削除
  - @zztkm
- [UPDATE] プロジェクト設定を Xcode のアップグレードチェック機能で自動更新
  - `BuildIndependentTargetsInParallel` の有効化
  - `ENABLE_USER_SCRIPT_SANDBOXING` の有効化
  - @zztkm
- [UPDATE] GitHub Actions のビルド環境を更新する
  - runner を macos-15 に変更
  - Xcode の version を 16.2 に変更
  - SDK を iOS 18.2 に変更
  - @zztkm
- [UPDATE] GitHub Actions の定期ビルドをやめる
  - @zztkm
- [ADD] swift-format 実行用の Makefile を追加する
  - format.sh で一括実行していたコマンドを個別に実行できるようにした
  - @zztkm

## sora-ios-sdk-2025.1.1

**リリース日**: 2025-01-23

- [UPDATE] Sora iOS SDK を 2025.1.1 にあげる
  - @miosakuma

## sora-ios-sdk-2025.1.0

**リリース日**: 2025-01-21

- [UPDATE] CocoaPods の platform の設定を 14.0 に上げる
  - @miosakuma
- [UPDATE] システム条件を変更する
  - iOS 14 以降
  - macOS 15.0 以降
  - Xcode 16.0
  - @miosakuma

## sora-ios-sdk-2024.3.0

**リリース日**: 2024-09-06

- [UPDATE] libwebrtc のログレベルを RTCLoggingSeverityNone から RTCLoggingSeverityInfo にする
  - libwebrtc のログを INFO レベルで出力するようにする
  - @zztkm
- [UPDATE] GitHub Actions の Xcode のバージョンを 15.4 にあげる
  - 合わせて iOS の SDK を iphoneos17.5 にあげる
  - @miosakuma
- [UPDATE] システム条件を変更する
  - macOS 14.6.1 以降
  - Xcode 15.4
  - WebRTC SFU Sora 2024.1.0 以降
  - @miosakuma

## sora-ios-sdk-2024.2.0

- [UPDATE] Github Actions を actions/cache@v4 にあげる
  - @miosakuma
- [UPDATE] Github Actions を macos-14  にあげる
  - @miosakuma
- [UPDATE] Github Actions を Xcode 15.2, iphoneos17.2 にあげる
  - @miosakuma
- [UPDATE] Github Actions のビルドオプションに `ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS=NO` を追加する
  - Xcode 15 で Asset のシンボルである、GeneratedAssetSymbols.swift が生成されるようになったがこのファイルが SwiftFormat エラー対象となる
  - CI では Asset のシンボル生成は不要であるため生成しないようオプション指定を行う
  - [Xcode 15 リリースノート - Asset Catalogs](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes#Asset-Catalogs)
  - @miosakuma
- [UPDATE] システム条件を変更する
  - macOS 14.4.1 以降
  - Xcode 15.3
  - Swift 5.10
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
