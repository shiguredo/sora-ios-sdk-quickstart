#!/bin/sh

# ローカルで lint と formatter を実行するスクリプト
# 未フォーマットか lint でルール違反を検出したら終了ステータス 1 を返す
# GitHub Actions では未フォーマット箇所の有無の確認に使う

# フォーマットリントは未フォーマットでもステータスコード 0 を返すので
# ステータスコードチェックを行わない
swift format lint -r Sora SoraTests
swift format -i -r Sora SoraTests

# TODO(zztkm): linter の実行どうしよう...

exit $?