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
| `local` | http://localhost:3000 |

## 環境變數

| 變數 | 用途 |
| --- | --- |
| `CBETA_XML` | cbeta-xml-p5a 目錄。`test_goto.rb` 的 `test_goto_works` 需要它逐一檢查所有典籍，未設定時該 test 會 skip。用 `rake remote:test` 會自動帶入 `config.cbeta_xml` |
| `CBETA_REFERER` | 送出 request 的 Referer，預設 `ray@dila.edu.tw` |
| `CBETA_API_KEY` | API key。帶了額度由 60 提高到 300 req/min，整套跑完快很多 |
| `CBETA_RATE_LIMIT` | 覆寫每分鐘的節流上限。與別人共用對外 IP 時可調低；設 `0` 表示完全不節流（校內 IP 已在 server 端豁免時用） |

## Rate limit

server 對未帶 key 的 request 限 **60 req/min/IP**、帶有效 key 限 **300 req/min/user**
（見 `app/controllers/concerns/api_key_authentication.rb`、`doc/api-key-design.md` 6）。
測試套件送的 Referer 不等於 Origin，所以**不帶 key 時一律算匿名**。

`run.rb` 會自動節流（sliding window，保證任何 60 秒內不超過額度），撞到 429 也會依
`Retry-After` 重試，因此不必手動加 sleep。未達上限前不會等待，單跑一個檔案仍是全速。

代價是整套跑完很慢：`test_goto_works` 會對全藏每部典籍各打一次 request（約 4000 次），
匿名約 74 分鐘，帶 key 約 15 分鐘。只想跑其他 test 時，不要帶 `CBETA_XML`
（直接用 `ruby test_remote/run.rb dev`），該 test 就會 skip。

## 新增 test

在本目錄新增 `test_xxx.rb`，`run.rb` 會自動 require。`run.rb` 提供 `get_json`、`get_text`、`get_html` 這些 helper，測試檔本身不需要處理 API base url。

測試過程產生的檔案請寫到 `TMP_DIR` (`tmp/test_remote/`)。
