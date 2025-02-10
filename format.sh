#!/bin/sh

# formatter を実行するスクリプト
# フォーマットリントは未フォーマットでもステータスコード 0 を返すので
# ステータスコードチェックを行わない
swift format lint -r SoraQuickStart
swift format -i -r SoraQuickStart

exit $?