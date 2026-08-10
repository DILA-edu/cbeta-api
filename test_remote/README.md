# 遠端 API 測試

打真正的 server (dev / stable / cn / test / local)，驗證 API 回傳結果。

**這些 test 不屬於 `bin/rails test`**：需要網路、比較慢、而且可能因為線上資料變動而失敗，所以放在 `test/` 之外，只在需要時手動執行。

## 執行

```sh
rake remote:test[dev]           # 測 dev，全部
rake remote:test[dev,search]    # 只跑 test_search.rb
rake remote:test[stable]        # 測 stable
```

也可以不經過 rake：

```sh
ruby test_remote/run.rb dev
ruby test_remote/run.rb dev search
```

## 可測試的 server

| 參數 | API |
| --- | --- |
| `dev` (預設) | https://cbdata.dila.edu.tw/dev |
| `stable` | https://cbdata.dila.edu.tw/stable |
| `test` | http://cbdata.dila.edu.tw/test |
| `cn` | https://api.cbetaonline.cn |
| `local` | http://localhost:3000 |

## 環境變數

| 變數 | 用途 |
| --- | --- |
| `CBETA_XML` | cbeta-xml-p5a 目錄。`test_goto.rb` 的 `test_goto_works` 需要它逐一檢查所有典籍，未設定時該 test 會 skip。用 `rake remote:test` 會自動帶入 `config.cbeta_xml` |
| `CBETA_REFERER` | 送出 request 的 Referer，預設 `ray@dila.edu.tw` |

## 新增 test

在本目錄新增 `test_xxx.rb`，`run.rb` 會自動 require。`run.rb` 提供 `get_json`、`get_text`、`get_html` 這些 helper，測試檔本身不需要處理 API base url。

測試過程產生的檔案請寫到 `TMP_DIR` (`tmp/test_remote/`)。
