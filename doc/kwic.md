# KWIC

## 執行步驟

    rake kwic:x2h
    rake kwic:h2t # 約 9.5 hrs
    rake kwic:sa  # 約 9.5 hrs
    rake kwic:sort_info
    rake kwic:rotate

## clear cache

kwic 所需的全部純文字檔，為了加速，存在 server cache 裡，
這些 cache 要記得更新。

run the following command in console

    Rails.cache.clear

This will clear the cache from whatever cache store you are using
