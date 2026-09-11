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

## 效能量測

`bench.rb` 量全文檢索各 endpoint 的回應時間，用來比較兩個 server（例如
Elasticsearch 的 dev 與 Manticore 的 stable），或比較同一個 server 改版前後。

```sh
rake remote:bench[dev,stable]   # 兩邊交錯跑，控掉時段差異
rake remote:bench[dev]          # 只跑一邊
ruby test_remote/bench.rb dev stable
```

每組查詢跑 5 次（1 次 cold + 4 次 warm），取 warm 的中位數。
量的是 API 自報的處理時間（回應的 `time` 欄位），不含網路往返；
wall clock 也一併記下來，兩者的差距就是網路加 Rails 的額外成本。
有 Rails cache 的 endpoint（`all_in_one` / `similar` / `variants`）一律帶
`cache=0`，量的是引擎的真實運算成本。

結果寫到 `tmp/bench/`（已 gitignore），之後可以拿兩份檔案對比：

```sh
rake remote:bench[compare,tmp/bench/舊.json,tmp/bench/新.json]
ruby test_remote/bench.rb compare tmp/bench/*.json
```

compare 會印出三張表：同功能的延遲比較、語法語意在新舊版不同因此不比倍率的
那幾項、以及各筆 `num_found` 是否一致。**改版前後的比較要看一致性那張表**——
快但結果變了不算改善。

從校外跑一定要設 `CBETA_RATE_LIMIT`，一輪是幾百個 request，否則必定撞 429：

```sh
CBETA_RATE_LIMIT=54 rake remote:bench[dev,stable]
```

## 環境變數

| 變數 | 用途 |
| --- | --- |
| `CBETA_XML` | cbeta-xml-p5a 目錄。`test_goto.rb` 的 `test_goto_works` 用它取得典籍清單，未設定時該 test 會 skip。用 `rake remote:test` 會自動帶入 `config.cbeta_xml` |
| `CBETA_GOTO_SAMPLE` | `test_goto_works` 每個藏經抽幾部典籍，預設 `20`（26 個藏經共約 360 次 request）。設 `0` 表示不抽樣，全藏約 4900 部全掃 |
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

## test_goto_works 的抽樣

整套測試的 request 有 99% 來自 `test_goto_works`：全藏約 4900 部典籍，每部各
打一次 goto。校內全掃一次約 4 分 45 秒，校外更久（匿名約 74 分鐘、帶 key 約
15 分鐘）。

所以預設改為**分層抽樣**：每個藏經抽 `CBETA_GOTO_SAMPLE` 部（預設 20，該藏
不足就全取），共約 360 次 request，整套約 30 秒跑完。分層而不是整體隨機，是
因為 goto 的眉角多半跟藏經有關（ZW 頁碼開頭是英文字母、J 的經號有 A/B 開頭），
整體隨機會讓小藏經幾乎抽不到。

抽樣用 `Random.new(Minitest.seed)`，所以同一個 `--seed` 抽到的典籍一樣，失敗
可以重現。

release 前或改動 goto 相關 code 時，建議全掃一次：

```sh
CBETA_GOTO_SAMPLE=0 rake remote:test[dev]
```

只想跑其他 test 時，不要帶 `CBETA_XML`（直接用 `ruby test_remote/run.rb dev`），
該 test 就會 skip。

## 新增 test

在本目錄新增 `test_xxx.rb`，`run.rb` 會自動 require。`run.rb` 提供 `get_json`、`get_text`、`get_html` 這些 helper，測試檔本身不需要處理 API base url。

測試過程產生的檔案請寫到 `TMP_DIR` (`tmp/test_remote/`)。
