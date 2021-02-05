# KWIC

## 工作資料夾

### 開發環境

    cd /Users/ray/git-repos/kwic25

### server

    cd ~/git-repos
    git clone git@gitlab.com:dila/kwic25.git

## 執行步驟

按照 ~/git-repos/kwic25/README.md 說明。

## clear cache

kwic 所需的全部純文字檔，為了加速，存在 server cache 裡，
這些 cache 要記得更新。

run the following command in console

    Rails.cache.clear

This will clear the cache from whatever cache store you are using
