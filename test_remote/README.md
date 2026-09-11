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
| `CBETA_RATE_LIMIT` | 每分鐘的節流上限。**預設 0 = 不節流**（校內 IP 在 server 端已豁免）。從校外跑才需要設 |

## Rate limit

**校內 IP 完全豁免 rate limit**（見 `doc/api-key-design.md` 3.4），所以在校內跑
預設不節流，整套可以全速跑完。

從校外跑才會受限：未帶 key **60 req/min/IP**、帶有效 key **300 req/min/user**
（見 `app/controllers/concerns/api_key_authentication.rb`、`doc/api-key-design.md` 6）。
注意測試套件送的是 Referer 而不是 Origin，所以**不帶 key 時一律算匿名**。

這時要自己設 `CBETA_RATE_LIMIT`（建議比 server 上限少約 10%，因為 client 與
server 的 window 邊界不會對齊）：

```sh
CBETA_RATE_LIMIT=54 rake remote:test[dev]                    # 未帶 key
CBETA_API_KEY=xxx CBETA_RATE_LIMIT=270 rake remote:test[dev] # 帶 key
```

設了之後 `run.rb` 會以 sliding window 節流（保證任何 60 秒內不超過該數字），
未達上限不等待，單跑一個檔案仍是全速。不論有沒有節流，撞到 429 都會依
`Retry-After` 重試。

校外跑整套會很慢：`test_goto_works` 會對全藏每部典籍各打一次 request
（約 4000 次），匿名約 74 分鐘、帶 key 約 15 分鐘。只想跑其他 test 時，
不要帶 `CBETA_XML`（直接用 `ruby test_remote/run.rb dev`），該 test 就會 skip。

## 新增 test

在本目錄新增 `test_xxx.rb`，`run.rb` 會自動 require。`run.rb` 提供 `get_json`、`get_text`、`get_html` 這些 helper，測試檔本身不需要處理 API base url。

測試過程產生的檔案請寫到 `TMP_DIR` (`tmp/test_remote/`)。
