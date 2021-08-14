#! /bin/bash

# エラー時に停止
set -eu -o pipefail

# エラー箇所出力
trap 'echo "ERROR: line no = $LINENO, exit status = $?" >&2; exit 1' ERR

# 各AWSリソース削除
cd ./terraform
terraform destroy
