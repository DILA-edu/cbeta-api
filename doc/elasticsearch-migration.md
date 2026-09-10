# Search engine 由 Manticore 改用 Elasticsearch — 遷移盤點

參考專案：`/Users/ray/git-repos/cbeta-api2`（Elasticsearch 搜尋 PoC，見該專案 `PLANS.md`）。

原則：原 endpoint 與參數儘量維持不變；需要改變的先討論。

## 0. 已定案

| 項目 | 決定 |
|---|---|
| 第一期範圍 | 只做 **text index**（`search`、`all_in_one`、`extended`、`facet`、`sc`、`variants`）；`notes`、`titles`、`chunks` 三個 index 暫時繼續走 Manticore，兩個後端並存 |
| extended syntax | **完整實作說明頁承諾的 7 項**（見 §A-1）。括號分組、`~n` 不做，遇到回 400 並記 log 觀察 |
| KWIC | **保留現有 `KwicService`**（suffix array），只把「候選卷取得 + 計數」換成 ES。KWIC 輸出與 8 項參數 100% 不變，也避開多詞 NEAR 的 Lucene highlight 500 風險 |
| index 命名 | **版本化 index + alias**（同 PoC）：實際 index 如 `cbeta_text_2026r1_001`，查詢走 `cbeta_text_current` alias，以 `elastic:promote` 原子切換 |
| 舊流程 | Manticore 的 rake tasks 與 `quarterly/section-manticore.rb` **保留一季**，新增 `elastic:*` 並行；`x2t` → `text.xml` 這段不可刪，ES 匯入就是吃它 |

## 0-1. 因「保留 KwicService」而得的簡化

PoC 為了走 ES highlight，索引存的是**含標點原文**，並在 analyzer 前掛 `mapping` char_filter 去標點、開 `term_vector: with_positions_offsets`，匯入時還要用逐卷原文（`TextContentSource`）覆寫 `content`。

本專案保留 `KwicService` 做顯示，**完全不需要 highlight**，因此：

| PoC 的做法 | 本專案 | 理由 |
|---|---|---|
| 索引含標點原文 + `mapping` char_filter 去標點 | **直接用 `text.xml` 既有的（已去標點）`content`** | 與現行 Manticore 完全同源，結果一致性最高；省掉 char_filter 與兩套正規化的同步守護 |
| `TextContentSource` 用逐卷原文覆寫 content | **不需要** | 不必依賴逐卷原文檔與行首對照檔 |
| `term_vector: with_positions_offsets` | **不開** | 只有 highlight 需要，省索引空間 |
| `_source` 存 content 全文 | **`_source` 排除 `content`／`content_without_notes`** | 與 Manticore 現況一致（`xmlpipe_field` 不存原文）；`term_freq` 計分走倒排索引，不受影響。將來若要改 highlight 需 reindex |

保留的是 PoC 的 `term_freq` scripted similarity（讓 phrase 查詢的 `_score` = 出現次數 × 詞長），這是取代 `ranker=wordcount` 的關鍵。

## A. extended syntax 清單

### A-1. API 說明頁對外承諾的語法

出處：`app/views/static_pages/search_extended.haml`、`_search-aio-q.haml`、`search_kwic.haml`。

| # | 語法 | 範例 | ES 對應 | `total_term_hits` 計法 |
|---|---|---|---|---|
| 1 | AND（空格分隔） | `"法鼓" "聖嚴"` | `bool.must` 多個 `match_phrase` | term_freq 相加，**需實測** |
| 2 | OR | `"波羅蜜" \| "波羅密"` | `bool.should` + `minimum_should_match: 1` | term_freq 相加，**需實測**（兩詞重疊時 Lucene phrase freq 與 Manticore wordcount 計法可能不同） |
| 3 | NOT | `"迦葉" !"迦葉佛"` | `bool.must_not` | ES 側 `must_not` 不計分；**Manticore 側 `weight()` 是否受影響需實測** |
| 4 | NEAR/n（兩詞） | `"法鼓" NEAR/7 "迦葉"` | `intervals.all_of`（`ordered: false`, `max_gaps: n`）— PoC 已有 | intervals `_score` 非出現次數，走 KWIC 逐卷計數 |
| 5 | NEAR/n（多詞鏈） | `"老子" NEAR/7 "道" NEAR/3 "經"` | 巢狀 `all_of` — **PoC 未支援，需新寫** | 同上 |
| 6 | Exclude（前／後搭配） | `"直心" -"正直心"`、`"舍利" -"舍利弗"` | `intervals` + `not_contained_by` — PoC 已有 | PoC 有 ES 快速路徑（兩次 phrase term_freq 掃描相減） |
| 7 | escape | `\"`、`\'`、`\-` | 解析層處理，與後端無關 | — |

### A-2. 程式碼有處理、但說明頁未寫的語法

| 語法 | 出現位置 | 備註 |
|---|---|---|
| `~n`（proximity） | `search_controller#init_notes` 會剝除 `~\d+$`；`kwic3#extended` 會剝除 `~\d+` | notes index 用，第一期不動 |
| `&` | `kwic3#extended` 會剝除 | `kwic3#extended` **沒有對外 route**，是 dead code |
| quorum `"…"/n` | `search#title`（`/3`）、`search#similar`（`/0.5`） | 由程式內部產生，非使用者輸入；ES 對應為 `minimum_should_match`。第一期不動（titles / chunks index 仍走 Manticore） |
| 括號分組 `(…)` | Manticore 原生支援，本專案未見使用 | 待確認是否需支援 |

### A-3. 待辦：production 語法分布

本機 log 沒有查詢紀錄（`log/development.log` 僅 24 筆），`Visit` model 統計的是佛典瀏覽而非查詢。
**需在 production 抓一次近一季 `search/all_in_one` 與 `search/extended` 的 `q` 分布**，統計 `|`、`!`、`~`、`&`、括號、多詞 NEAR 各出現幾次，用以確認「完整實作」的實際範圍。

## B. KWIC 功能對照

前提釐清：
- 本專案的 `KwicService` **完全不依賴 Manticore**（走 suffix array `data/kwic/sa` + 純文字 `data/kwic/text`），換 ES 時可以原封不動保留。
- `search/kwic` → `kwic3#juan` 只走**單卷** suffix array（`search_sa_juan`）。`KwicService#search` 的全藏 concordance **沒有對外 route**，不在遷移範圍。
- PoC 的 KWIC 經過兩階段：早期用純文字檔比對（`CbetaKwic::TextService#search`），2026-07-09 起顯示端**全面改用 ES highlight**，`TextService` 現在只負責計數與匯入讀原文。

### B-1. 功能對照表

| 功能／參數 | 本專案 `KwicService` | PoC（ES highlight） | 若走 highlight 要補的工作 |
|---|---|---|---|
| 單卷 `work` + `juan` | ✅ | ✅ | — |
| 多關鍵字（半形逗點） | ✅ `q=法鼓,聖嚴` | ❌ | 解析後多次查詢合併 |
| NEAR（兩詞） | ✅ | ✅ | — |
| NEAR（多詞鏈） | ✅ `search_near_juan` | ❌ | 巢狀 `all_of`；**有 highlight 風險，見 B-2** |
| `negative_lookahead` / `negative_lookbehind` | ✅（獨立參數） | ✅（但走 `q` 的 `-"…"` 語法） | 參數名對應轉換 |
| `sort=f` / `sort=b` | ✅（suffix array 天然排序） | ❌（固定依位置） | 單卷資料量小，Ruby 端對命中後文／前文字串排序即可 |
| `sort=location` | ✅ | ✅（等同預設） | — |
| `place=1`（地理資訊） | ✅ | ❌ | 由 `Work` model 補欄位，與搜尋後端無關 |
| `word_count=n`（前後字統計） | ✅ 回 `prev_word_count`／`next_word_count` | ❌ | 可由 highlight 結果在 Ruby 端統計 |
| `kwic_w_punc` / `kwic_wo_punc` | ✅ | ❌（只有含標點） | 需另存或即時產生無標點版本 |
| `seg=1`（自動分詞） | ✅（`WordSegService`） | ❌ | 對 kwic 字串後處理，與後端無關 |
| `note=0`（不含夾注） | ✅（`sa-without-notes`） | ❌（PoC 的 kwic 固定查 `content`） | 改查 `content_without_notes`（欄位已存在） |
| `mark`、`around`、`rows`、`start` | ✅ | ✅ | — |
| `referer_cn` 屏蔽 | ✅ | ❌ | 需補 |
| 回傳欄位 `lb`、`vol` | ✅ | ❌（只回 `work`／`juan`／`linehead`／`kwic`） | `linehead` 含同等資訊，但欄位名與格式需對齊 |
| `linehead` | ✅ | ✅（行首對照檔二分搜尋） | 需先產行首對照檔 |

**結論：PoC 的 `/search/kwic` 並未完整實作原 `KwicService` 的功能，缺 8 項**（多關鍵字、多詞 NEAR、`sort=f/b`、`place`、`word_count`、`kwic_wo_punc`、`seg`、`note=0`），另有 `referer_cn` 與回傳欄位差異。

### B-2. 輸出結構差異與已知風險

- **NEAR 的結果結構不同**：`search_near_juan` 對每個命中詞各回一筆（帶 `offset_in_text_with_punc` 排序）；ES intervals 的 highlight 會把整個命中區間合併成一筆。
- **highlight 無法精確計數**：重疊或相鄰的出現會被合併成單一標記區間（搜「哈哈」遇「哈哈哈」只標一次，正確計數應為 2），故 KWIC 筆數可能少於 `total_term_hits`。
- **多詞 NEAR 的 highlight 有 Lucene bug 風險**：PoC 的 `PLANS.md` 記錄，`all_of` 子區間覆蓋 ≥13 個 token 時，Lucene 的 `CachingMatchesIterator` 陣列越界，**整個查詢回 500**（上游 2021 後未修）。不帶 highlight 的查詢不受影響。多詞 NEAR 鏈的巢狀 `all_of` 很容易撞到這個上限。
- **改走 highlight 的好處**：查詢語意只在 ES query 定義一次，顯示端與查詢類型解耦——extended syntax 每新增一種查詢型態，`KwicService` 不必跟著另寫一套比對邏輯。這正是「完整實作 extended syntax」這個決定會放大的成本差異。

## C. 其他技術落差（第一期必須處理）

| 項目 | 說明 |
|---|---|
| `ranker=wordcount` → `_score` | PoC 用 `term_freq` scripted similarity 讓 phrase 查詢的 `_score` = 出現次數 × 詞長，語意可對上 |
| facet 的 `hits`（`SUM(weight())`） | **ES 的 aggregation 無法 sum `_score`**。要維持現有回傳格式，需改成「PIT + `search_after` 掃出全部候選（含 `_score` 與 facet 欄位），在 Ruby 端聚合」。PoC 實測 7,700 卷掃描約 21ms，可行；輸出欄位可完全不變 |
| 深分頁 | ES 預設 `from + size ≤ 10000`，現行 API `start` 可到 99999。需調高 `index.max_result_window` 或改走 `search_after` |
| `estimate_max_matches` | Manticore 的 `max_matches` 概念在 ES 不存在，該段可直接移除 |
| index 命名與輪替 | PoC 用版本化 index 名 + `cbeta_text_current` alias（`elastic:promote` 切換）。本專案現行是 `text#{cb.v}` 季號命名 + symlink 輪替，需決定對應方式 |
| 連線設定放哪 | PoC 走 ENV（`ELASTICSEARCH_URL`、`CBETA_ES_INDEX_NAME`）。本專案可放 `config/cb.yml`（gitignored）或 `config/application.rb` + ENV |
| 本機開發環境 | 目前 Docker 未啟動、本機無 ES。需 `colima start` + PoC 的 `compose.elasticsearch.yml`（ES 9.4.2） |

---

# 第一期實作結果（2026-09-08）

## 新增與修改的檔案

| 檔案 | 說明 |
|---|---|
| `Gemfile` | 新增 `elasticsearch ~> 9.4` |
| `config/application.rb` | 新增 `config.x.elasticsearch.*`（連線、alias、index 名稱、text.xml 路徑）；`config.x.se.*`（Manticore）保留 |
| `compose.elasticsearch.yml` | 本機開發用單節點 ES 9.4.2（`127.0.0.1:9200`、heap 2g） |
| `app/services/cbeta_search/elastic_client.rb` | ES client 建構 |
| `app/services/cbeta_search/text_index.rb` | index mapping、建立、匯入、alias 切換、token 數計算 |
| `app/services/cbeta_search/manticore_text_xml_reader.rb` | 逐份讀取 `text.xml`（1.3GB，不載入整份 DOM） |
| `app/services/cbeta_search/query.rb` | 解析後的查詢結構 |
| `app/services/cbeta_search/query_parser.rb` | extended syntax 解析（7 種語法） |
| `app/services/cbeta_search/elastic_query_builder.rb` | 組 ES query（filter、排序、計分） |
| `app/services/cbeta_search/search_service.rb` | 搜尋、計數、facet、候選卷取得 |
| `app/controllers/search_controller.rb` | text index 相關 action 改走 ES；移除 `exclude_by_sphinx`、`facet_by_sphinx_all`、`sphinx_search_simple` |
| `lib/tasks/elastic.rake` | `elastic:start/stop/status/info/create_index/import_text/promote/rebuild/analyze/fetch_golden/verify_golden` |
| `test/services/cbeta_search/*_test.rb` | 49 個測試（語法解析、query body、token 切分同步） |
| `test/fixtures/files/elastic/text.xml` | 130 卷的小型匯入 fixture |
| `test/fixtures/files/search_golden_2026R1.json` | 從 production 抓的驗收基準 |

## 三個關鍵技術決定（都是實測後才定的）

### 1. tokenizer 用 `pattern`，不是 `ngram` 也不是 `standard`

Manticore 的 `charset_table = non_cjk` + `ngram_len = 1` 是「CJK 逐字切、拉丁按 word 切」。

- **純 `ngram(1,1)`（PoC 的做法）不行**：拉丁文被逐字元切開，搜「Ananda」會誤中「Pannananda」「Satyananda」「Śikṣānanda」等較長字的子字串 —— 實測比 production 多出 14 卷。
- **`standard` tokenizer 不行**：會丟掉「□」(U+25A1)、「▆」(U+2586) 與 PUA 缺字，而這三者在 CBETA 都是有意義的正文字元。
- **`pattern` tokenizer 可行**：`[拉丁字母數字]+|[^\s]` —— 連續拉丁字母算一個 token，其他每個非空白字元各一個。實測完全對應 Manticore（含 □、▆、PUA、康熙部首、相容漢字）。

另外加 `asciifolding` token filter，對應 `non_cjk` 的變音符號折疊（實測 production：`Ananda` 與 `Ānanda` 同得 52 卷）。

### 2. `term_hits` 用 `script_score` 除以 token 數，不是 query boost

`content` 掛 `term_freq` scripted similarity 後，`match_phrase` 的 `_score` = 出現次數 × token 數。要還原成「出現次數」必須除以 token 數，否則多個詞組相加時會被詞長加權（與 Manticore `ranker=wordcount` 不符）。

- **query 層級的 `boost` 對 scripted similarity 無效**（實測會被完全忽略，改 script 為 `weight * doc.freq` 也一樣）。
- **正解是 `script_score` query**：`_score / <token 數>`。實測 AND、OR 的各詞次數都能正確相加。
- 除數必須是 **token 數**而非字元數（「Ānanda」是 1 個 token、「Pāli Text Society」是 3 個）。Ruby 端的 `TextIndex.token_count` 與 ES 的切分規則有單元測試守護。

### 3. `total_term_hits` 必須另發一次 `size: 0` 的查詢

不能和「取當頁結果」的查詢合併：取當頁（`size > 0`）時 Lucene 會做 top-k 動態剪枝，沒機會進入 top-k 的文件不會被精確計分，同一個 request 裡的 aggregation 因此拿到偏低的總和 —— 實測「波羅蜜」合併查詢得 59262，正確值 111691。

舊版 Manticore 也是分成 `SELECT` 與 `SELECT SUM(weight())` 兩道 SQL，成本相當。

`facet` 的 `hits` 同理，用 `terms` aggregation 搭配 `scripted_metric` 子 aggregation（ES 的 aggregation 無法直接 `sum(_score)`）。

## 驗證結果

驗收工具：`rake elastic:fetch_golden[<url>]` 抓基準、`rake elastic:verify_golden[<url>]` 比對。

**本機 `data/manticore-xml/text.xml` 比 production 舊**（只到 YP0021，production 有 YP0023 以後），因此有一批系統性的小差異。已用 canon facet 做決定性驗證：

> 「法鼓」的 24 個藏經 facet 中 **21 個 docs/hits 完全一致**，只有 B、G、YP 三藏有差，合計差 7 卷 7 hits —— **恰好等於該查詢的總差異**（1106→1099、1582→1575）。

也就是說剩餘差異 100% 來自資料版本，程式邏輯與 Manticore 一致。

**完全一致的項目**（17 項）：
- AND（`"法鼓" "迦葉佛"` → 109 卷 / 373 hits，逐字相符）
- 拉丁文與變音符號（`Pāli Text Society`、`Ānanda`、`Ananda`、`samantato \'nantanāvāptiśāsani`）
- 組字式 PUA 缺字（`[幻-ㄠ+糸]`）、相容漢字（U+2F8BB → 170 卷 / 3231 hits）、康熙部首（U+2F94 → 0 卷）
- 全部 filter：`canon`（單值與多值）、`category`、`creator`、`dynasty`、`time`
- 全部 facet：`canon`（24 筆）、`dynasty`（27 筆）、`category`（22 筆）

**差異在資料版本範圍內**（-0.4% ~ -2.4%，方向一致）：基本查詢、OR、NOT、Exclude（前／後搭配）、`work_type`、`note=0`、各種 order、分頁、`sc`。

**尚未驗證**（本機環境限制，非程式問題）：
- `all_in_one` 的 KWIC 路徑（NEAR、以及預設會回 `kwics` 的查詢）：本機 `data/kwic/sa` 只有 135 卷（完整需 22,037 卷），`search/kwic` 同樣失敗，證明是既有的環境資料缺口。
- `variants`、`notes`、`title`、`similar`：需要 Manticore，本機沒有。

## 行為改變（2026-09-08 已與主管確認，版號定為 5.0.0）

| # | 項目 | 舊版 | 新版 |
|---|---|---|---|
| 1 | `search` / `search/extended` 的 `q` 帶雙引號 | **語法失效**：`q="法鼓"` 被再包一層引號，變成「法」AND「鼓」，得 8520 卷（說明頁承諾的是 phrase） | 正確解析為詞組，得 1106 卷。`all_in_one` 本來就是對的，現在三個 endpoint 行為一致 |
| 2 | 回傳的 `SQL` 欄位 | 回傳內部 SQL 語句 | 移除（避免洩漏內部查詢細節） |
| 3 | 排序值平手時的順序 | 不可預期的內部 doc id 順序（實測同一部典籍的卷 3 會排在卷 1 前面） | 一律補上 `canon_order, work, juan` 作為最後比較依據，分頁結果可預期 |
| 4 | `search` / `search/extended` 的 NEAR 與 Exclude | 被當成詞組的一部分，搜不到 | 支援。Exclude 有精確的 `total_term_hits`；NEAR 只回 `num_found`（精確計數請用 `all_in_one`，那裡有 KWIC 逐卷計算） |
| 5 | 不支援的語法 | Manticore 自行解讀（結果難預期） | 括號分組、`~n`、`&` 一律回 400 並說明 |
| 6 | `start` 超出範圍 | 由 `max_matches`（99,999）決定 | `start + rows` 上限 100,000（`index.max_result_window`），超過回 400 |
| 7 | `search/facet` 遇到 NEAR／Exclude | 當成詞組，回空陣列 | 回 400。intervals 的 `_score` 不是出現次數，加總出來的 `hits` 沒有意義 |

## 部署待辦

操作步驟（compose.yaml、cb.yml 片段、每季流程、疑難排解）見
[elasticsearch-deploy.md](elasticsearch-deploy.md)。

- [ ] 在 `sakya.dila.edu.tw` 安裝 Elasticsearch 9.4.2（docker，照 Manticore 的慣例放 `/home/ray/cbeta-es/compose.yaml`）

  伺服器現況（2026-09-08 實測）：10 核、94GB 記憶體（實際使用 5.7GB）、磁碟 1TB 用 44%、
  port 9200 未被佔用（Manticore 用 9307）、已有 docker（`manticore3` 容器用 7.45GB）。
  ES index 實測 1.4GB / 22,037 卷，heap 4GB 即足夠 —— 對現有服務的影響可忽略。

  **與 Manticore 的兩個差異**：
  * port 建議綁 `127.0.0.1:9200`。Manticore 目前綁 `0.0.0.0:9307`（compose 註解寫明「允許
    server 外連線」），但 ES 的 PoC 設定關掉了 `xpack.security`，不可對外曝露。
  * **不需要 slot 輪替目錄**。Manticore 每季要新建 `/var/lib/manticoreN`、改 conf、restart
    容器；ES 只要 `elastic:rebuild` 建新的版本化 index、再 `elastic:promote` 切 alias，
    容器完全不用動。

- [ ] **staging 與 production 的 index 必須隔離**：兩者是同一台機器（`sakya.dila.edu.tw`，
  只有 `deploy_to` 不同），共用同一個 ES 服務。若兩邊都用預設 alias `cbeta_text_current`，
  staging 重建 index 就會影響 production。作法：各自的
  `shared/config/cb.yml`（每個 deploy 一份、gitignored）設不同的 `elasticsearch.index_alias`，
  例如 production 用 `cbeta_text_current`、staging 用 `cbeta_text_staging`。

- [ ] 在各環境的 `config/cb.yml` 加 `elasticsearch:` 區塊（`url`、`index_alias`，
  選用 `index_name`／`request_timeout`）
- [ ] 每季流程加入 `rake elastic:rebuild[cbeta_text_<季號>_NNN]`（吃 `manticore:x2t` 產出的 `text.xml`，22,037 卷約 2.5 分鐘）
- [ ] 切換後 flush Rails cache（cache key 沒變，但內容來自不同後端）
- [x] 更新對外更新紀錄 `static_pages/log.haml`（2026-09 Version 5.0.0）
- [x] 更新 API 說明頁（2026-09-08）：`search_extended.haml` 改寫雙引號說明、補上多詞 NEAR／Exclude／不支援語法；`search.haml` 補上可用 Extended 語法、改掉 Manticore 特有的「排序欄位最多五個」限制
- [ ] 過渡期結束後移除 Manticore 的 rake tasks、`quarterly/section-manticore.rb`、四個 `manticore-template-*.conf`（`x2t` → `text.xml` 這段要留）

---

# 第二期盤點：notes / titles / chunks（2026-09-10）

第一期已把 text index 搬到 Elasticsearch 並隨 2026R3 的 `rake quarterly` 在 server 上跑完。
第二期的目標是把剩下三個 Manticore index 也搬過去，讓 Manticore 完全退場。

## D. 現況：還在用 Manticore 的地方

| 進入點 | index | 查詢方式 | 後處理 |
|---|---|---|---|
| `search#notes` | `notes<v>` | `MATCH('<q 原樣>')` + filter，`ranker=wordcount`，`ORDER BY canon_order, vol, lb` | `notes_highlight`（Ruby 端加 `<mark>`） |
| `search#title` | `titles<v>` | `MATCH('"逐字空格"/3')` quorum，**無 ORDER BY**（依 Manticore 預設 `proximity_bm25` 相關度） | `mark_title`、補 `Work` 欄位 |
| `search#similar` | `chunks<v>` | `MATCH('"<q>"/0.5')` quorum，`ranker=proximity_bm25`，取 top k（預設 500） | Smith-Waterman 比對、去重、依 score 排序 |
| `search#variants`（`scope=title`） | `titles<v>` | `MATCH('@content "<phrase>"')`，`SUM(weight())` | — |
| `exist_in_cbeta`（`variants` 用） | `notes<v>`、`titles<v>` | `MATCH('"<q>"') LIMIT 1` | text 部分已走 ES |
| `rake import:vars` | **`text<v>`** | 自己有一份 `exist_in_cbeta`，查的是 **Manticore 的 text index**（`config.x.se.index_text`），不是 controller 那一份 | — |

其餘 Manticore 相關檔案：`ManticoreService`、`lib/tasks/manticore/*`、
`lib/tasks/quarterly/section-manticore.rb`、四個 `manticore-template-*.conf`、
`config.x.se.index_*`。

## E. 好消息：analyzer 完全共用

四個 `manticore-template-*.conf` 的切詞設定**逐字相同**：

```
charset_table = non_cjk
ngram_len = 1
ngram_chars = cjk, U+2580..U+25FF, U+2F00..U+A4CF, U+F900..U+FAFF, U+FE30..U+FE4F, U+20000..U+2FA1F
```

因此第一期實測定案的 `cbeta_text` analyzer（`pattern` tokenizer + `lowercase` +
`asciifolding`，見 `TextIndex::TOKEN_PATTERN`）可原封不動套用到三個新 index，
不需要重新實測切詞規則。

## F. 三個 index 的差異與難點

### F-1. notes（難度：低）

* **語法**：說明頁只承諾 AND／OR／NOT／NEAR 四項，全部落在現有 `QueryParser` 的能力內。
* **`_source` 要存 content**：與 text 相反。notes 回傳 `content`，`notes_highlight`
  還要用 `content_w_puncs`／`prefix`／`suffix`，都必須存進 `_source`。
  只有 `content`（去標點版）需要索引；`content_w_puncs` 在 Manticore 是 string
  attribute，本來就不進 index。
* **`term_hits` 與 `total_term_hits`**：逐筆結果沒有 `term_hits`（`init_notes` 的欄位
  清單沒有 `weight()`），但**回傳的最外層有 `total_term_hits`**（實測 `/dev`：
  `q="法鼓"` → `num_found=60`、`total_term_hits=67`）。因此 `content` 仍要掛
  `term_freq` similarity，`facet=1` 的 `hits` 也照 text 的 `scripted_metric` 做法。
* **排序**：預設 `canon_order, vol, lb` 三個都是 keyword，ES 直接排即可。
  但 `ElasticQueryBuilder::SORT_FIELDS` 與 `TIEBREAKER` 是 text 專用的
  （沒有 `lb`／`n`／`note_place`），要改成每個 index 一組排序設定，不能共用常數。

行為改變（與 text 第一期同型）：

| # | 項目 | 舊 | 新 |
|---|---|---|---|
| 1 | 回傳的 `SQL` 欄位 | 有（實測 `/dev` 仍回傳） | 移除，同 text 的第 2 項 |
| 2 | NEAR 的 `total_term_hits` | Manticore `ranker=wordcount` 算得出（實測 `"阿含" NEAR/5 "迦葉"` → 3） | intervals 的 `_score` 不是出現次數，且 notes **沒有** KWIC suffix array 可退回逐筆計數，只能回 `num_found` |
| 3 | NEAR + `facet=1` | 有數字（意義存疑） | 回 400，同 text 的第 7 項 |
| 3b | NEAR 的距離邊界 | Manticore 是「相隔 < n 字」（實測 `ES(n) ≡ Manticore(n+1)`） | 「相隔 ≤ n 字」—— 與說明頁寫的「距離不超過 n 個字」及 `KwicService#check_near`（`pos2 - pos1 - q1.size <= near`）一致。Manticore 才是例外，`search/all_in_one` 本來就是新的這個語意 |
| 4 | `~n` | 原樣送進 Manticore（`init_notes` 裡剝除 `~\d+$` 的那段是 dead code，算出來的 `s` 沒被用到） | 回 400，同 text 的第 5 項 |
| 5 | `start` 超出範圍 | `estimate_max_matches` 算出的 `max_matches` | `MAX_RESULT_WINDOW` 上限，同 text 的第 6 項 |
| 6 | `work_type` filter | notes index 沒有這個欄位，Manticore 回 500（`unknown column`） | ES 對不存在的欄位做 filter 會安靜地回 0 筆。說明頁的「限制搜尋範圍」本來就沒承諾 notes 支援 `work_type`，但行為從報錯變成空結果 |

### F-2. titles（難度：低，但排序一定會變）

* **quorum `/3` 實測結果**：`/dev` 的 `q=法鼓`（2 字）回 2 筆、`q=經`（1 字）回 2272 筆。
  也就是 **keyword 數少於 3 時，quorum 退化成「全部都要命中」，不是回 0 筆**。
  ES 對應為 `match` + `minimum_should_match: [3, token 數].min`（**不是** `match_phrase`）。
* **similarity 用預設 BM25，不掛 `term_freq`**：這裡要的是相關度，不是出現次數。
* **排序一定會變**：現行 SQL 沒有 `ORDER BY`，靠 Manticore 預設的 `proximity_bm25`；
  ES 用 Lucene BM25。兩者演算法不同，**同分與相近分數的順序必然不同**。
  這是無法做到 100% 一致的一項，需要接受。
* **latin 切詞的邊界差異**：Manticore 收到的是 `@q.chars.join(' ')`（逐字空格分開），
  拉丁字母因此一字一 keyword；ES 若直接 `match` 原始 `@q`，analyzer 會把連續拉丁字母
  併成一個 token。經名裡的拉丁字很少，但行為不同，要在實作時決定沿用哪一種。
* **`variants` 的 `scope=title` 計數**：`SUM(weight())` 是 phrase 出現次數
  （實測 `q=神咒&scope=title` → `神呪` 31）。titles.xml 只有 742KB，
  **建議 `content` 多開一個掛 `term_freq` 的 sub-field**（一個給 BM25 排序、
  一個給計數），成本可忽略，且回傳數字完全不變。
* **filter 支援範圍**：titles index 只有 `work`／`canon`／`canon_order` 三個屬性。
  實測 `/dev` 的 `/search/title?q=觀無量壽經&dynasty=唐` 回
  `table titles3: unknown column: dynasty`，**而且把 backtrace（含伺服器路徑）一起回傳**。
  搬到 ES 時至少要讓它變成乾淨的錯誤；titles.xml 由 `Work` model 產生，
  要補齊 dynasty／category／creator／time 也很容易。

### F-3. chunks / similar（難度：高，一致性最差）

* **index 體積**：`chunks.xml` 本機 3.7GB（text.xml 的 3 倍；每 100 字一塊、
  前後重疊 50 字）。ES index 估計 4~5GB，是三者中最大的。
* **`_source` 必須存 content**：Smith-Waterman 要拿全文比對。
* **top-k 的組成會變**：第一階段是 `quorum /0.5` + `proximity_bm25` 取前 500。
  Lucene BM25 與 Manticore proximity_bm25 的排序不同 → **進入 Smith-Waterman 的
  500 筆候選不會完全一樣 → 最終結果必然有出入**。這一項無法用「資料版本差異」解釋掉，
  是演算法差異。
* 因此建議把 `similar` 排在最後，且先確認它的實際使用量（同 §A-3 一直沒做的 production
  log 統計）。

## G. 第一期遺留：`rake import:vars` 還在用 Manticore 的 text index

`lib/tasks/import/vars.rake` 有自己的 `exist_in_cbeta`，`@index` 直接取
`Rails.configuration.x.se.index_text`，第一期沒有一起改。也就是說：

* **Manticore 的 text index 目前還不能停**，否則 `rake import:vars` 會壞。
* `section_manticore` 裡的 `step_manticore_vars` 排在 `section_elastic` **之前**。
  改用 ES 之後，`import:vars` 必須移到 `elastic:rebuild` 之後 —— 這不是選項，是必要的重排。

修法：把 `ImportVars#exist_in_cbeta` 換成
`CbetaSearch::SearchService#exist?`（controller 已經是這樣做了）。

## H. 決策（2026-09-10 已確認）

| # | 項目 | 內容 | 決定 |
|---|---|---|---|
| 1 | 本期範圍 | notes + titles + `import:vars` | **已定案**。做完後 Manticore 只剩 `chunks` 一個 index（`search/similar` 用） |
| 2 | `similar` 的排序差異 | 接受 Lucene BM25 的結果差異 | **已定案：接受，照搬**。排在第三期，屆時 `search_similar.haml` 的「第一階段使用 Manticore 模糊搜尋」也要改寫 |
| 3 | `variants` 的 `scope=title` 計數 | 保留「出現次數」，或改回「文件數」 | **保留出現次數**。titles.xml 只有 742KB，多一個 `term_freq` sub-field 成本可忽略，回傳數字完全不變 |
| 4 | `/search/title` 的 filter | 維持現狀（只支援 canon），或補齊 dynasty／category／creator／time | **補齊**。現況是回 500 並洩漏 backtrace，本來就該修 |
| 5 | rake 介面 | `elastic:rebuild[<type>,<index_name>]` 加型別參數，或各自 `elastic:rebuild_notes[...]` | 加型別參數，另提供 `elastic:rebuild_all[<季號>]` 一次做完 |
| 6 | alias 命名 | `cbeta_notes_current`／`cbeta_titles_current`（staging 各自 `_staging`）；cb.yml 從單一 `index_alias` 改成每個 index 一組 | 照此辦理，cb.yml 改成 `elasticsearch.aliases.{text,notes,titles}` |
| 7 | Manticore 退場時機 | 本期一併移除，或再保留一季 | 保留到 chunks 也搬完為止（本期結束後 Manticore 只剩 `chunks` 一個 index，conf 與 quarterly 步驟可先精簡） |

## I. 驗證計畫

第一期文件記的「`notes`／`title`／`similar`／`variants` 在 staging 驗不了（Manticore r3
index 不存在）」已經解除 —— 2026R3 的 `rake quarterly` 跑完了，`/dev` 現在有可用的
Manticore 結果。因此：

* golden 從 `/dev` 抓（與 staging 的 XML 同季），擴充 `elastic:fetch_golden` 的案例清單，
  加入 `search/notes`、`search/title`、`search/similar`、`search/variants`。
* **本機資料版本比 text 更亂**：`notes.xml`／`chunks.xml` 是 2026-03、`text.xml` 是
  2026-06、`titles.xml` 是 2026-05。本機只能驗語法與結構，數字一致性要在 server 上驗。

---

# 第二期實作結果（2026-09-10）

範圍：`notes`、`titles` 兩個 index 與 `rake import:vars`。
`search/similar`（chunks index）仍走 Manticore，排在第三期。

## 新增與修改的檔案

| 檔案 | 說明 |
|---|---|
| `app/services/cbeta_search/index_base.rb` | 新增。三個 index 共用的 analyzer、similarity、建立／匯入／alias 切換 |
| `app/services/cbeta_search/text_index.rb` | 改為繼承 `IndexBase`，欄位／排序設定收斂成 class 方法 |
| `app/services/cbeta_search/notes_index.rb` | 新增 |
| `app/services/cbeta_search/titles_index.rb` | 新增 |
| `app/services/cbeta_search/manticore_xml_reader.rb` | 由 `manticore_text_xml_reader.rb` 改名，欄位型別轉換改由呼叫端指定 |
| `app/services/cbeta_search/elastic_query_builder.rb` | 依 index 參數化；新增 `:quorum` 查詢；bool 查詢外包 `script_score`（見下） |
| `app/services/cbeta_search/search_service.rb` | 可指定 index；`row_from_hit` 依 index 的 `row_fields`；新增 `exist_all?`（`_msearch` 批次） |
| `app/services/cbeta_search/query.rb` | 新增 `:quorum` 型別 |
| `app/controllers/search_controller.rb` | `notes`／`title`／`variants` 改走 ES；移除 `sphinx_search`／`sphinx_select`／`sphinx_total_found`／`facet_by_sphinx`／`get_hit_count`／`exist_in_index`／`estimate_max_matches`／`init_order`（**淨減 375 行**） |
| `config/application.rb` | 新增 `CbetaEsAlias`（由 text alias 推導其他 alias）、`config.x.elasticsearch.aliases`／`.xml` |
| `lib/tasks/elastic.rake` | 所有 task 加 index 種類引數；新增 `elastic:rebuild_all[<季號>]`；golden 案例由 31 增為 45 |
| `lib/tasks/import/vars.rake` | 改用 `SearchService#exist_all?`（只查 text index，與 controller 的三 index 版刻意不同） |
| `lib/tasks/manticore/titles.rake` | titles.xml 補上朝代／部類／作譯者／年代 |
| `lib/tasks/quarterly/section-elastic.rb` | 一次建三個 index；接手原本在 manticore section 的 `import:vars` |
| `lib/tasks/quarterly/section-manticore.rb` | 移除 `step_manticore_vars` |
| `test/services/cbeta_search/index_definitions_test.rb` | 新增。三個 index 的 mapping、alias 推導、index 命名 |

## 途中發現的兩個 Elasticsearch 問題（都已修正）

這兩個都是**規模相依**的：22,037 筆的 text index 不會出現，2,182,414 筆的 notes index 必現。

### 1. `norms` 開著會讓大 index 的 OR 查詢回 500

`term_freq` scripted similarity 只用 `doc.freq`，不用 `doc.length`，但 mapping 沒關掉 norms。
「OR 查詢 + `scripted_metric` 讀 `_score`」時，`ScriptedSimilarity` 會對已走完的 scorer
（docID = `Integer.MAX_VALUE`）去讀 norms：

```
java.io.EOFException: read past EOF (pos=2147483647) ... [slice=_10.nvd]
```

`_forcemerge` 成單一 segment 後依然重現，確定不是 segment 損壞。
**修正**：全文欄位一律 `norms: false`。分數完全不變（實測單一詞組前後都是 3084），
index 還小了約 2%。

### 2. bool 查詢的 `total_term_hits` 會少算

bool 有多個計分子句時 Lucene 走 block-max WAND，部分文件只算到其中一個子句的分數。
實測 notes index：

| 查詢 | 現行寫法 | 正確值 | Manticore |
|---|---|---|---|
| `"波羅蜜" \| "波羅密"` | 3090 | 3204（= 3084 + 120） | 3204 |
| `"波羅蜜" \| "般若"` | 7334 | 9513（= 3084 + 6429） | — |

**修正**：`bool_query` 外面再包一層 `script_score`，`source` 就是 `"_score"`
（分數不變），強迫內層以 COMPLETE 模式計分。text index 兩種寫法同值，
但因為是規模相依的，一律外包。

## 驗證結果

驗證條件比第一期嚴格得多：**把 staging 的 `text.xml`／`notes.xml`／`titles.xml`
（2026R3，2026-09-09 產出）抓到本機重建三個 index**，golden 從 `/dev` 抓，
因此可以逐筆精確比對，不必用「差異落在資料版本」來解讀。

`rake 'elastic:verify_golden[http://localhost:3000]'`：**45 項中 42 項完全一致**。

三項差異全部有明確歸因：

| 案例 | 狀況 |
|---|---|
| `aio_near2`／`aio_near3` | 本機 `data/kwic/sa` 只有 135 卷（完整需 22,037 卷），KWIC 讀檔失敗。既有的環境資料缺口，與這次改動無關 |
| `notes_near` | 刻意的行為改變，見 F-1 的第 3b 項（NEAR 距離邊界的 off-by-one） |

另外逐項比對過、golden 沒涵蓋的部分：

* `notes` 的 5 種 facet（canon／category／creator／dynasty／work）**所有項目逐筆相符**。
* `notes` 的回傳欄位與舊版完全相同（`id, note_place, canon, category, vol, file,
  work, title, juan, lb, n, content, highlight`），只少了除錯用的 `SQL`。
* `title` 的 quorum：1 字（2272）、2 字（2）、5 字（51）、8 字（248）全部與 `/dev` 相同 ——
  含 §F-2 實測到的「字數少於門檻時退化成全部都要命中」。
* `title` 的回傳欄位與舊版相同。
* `variants`：`神咒`（4963）、`神咒&scope=title`（神呪 31）、`著衣持鉢`（51/3/17）、
  `無上正等正覺`（[]）四例的 `q` 與 `hits` 全部相符。
  這同時驗證了 `import:vars` → `Variant` 表 → `exist_in_cbeta` → `hit_count` 整條鏈路。
* `/search/title` 加 filter 不再回 500：`dynasty=唐`（8）、`category=淨土宗部類`（34）、
  `canon=T`（35）、`time=600..700`（6）。

### `import:vars` 的結果差異：ES 比 Manticore 多收 107 個異體字

拿 staging（Manticore、同一份 text.xml）比對：

| | 記錄數 | 異體字總數 |
|---|---|---|
| staging（Manticore） | 36,603 | 50,098 |
| 本機（Elasticsearch） | 36,706 | 50,205 |

差異是 **ES 多收 102 個字元、107 個 (key, 異體字) 配對；Manticore 沒有多收任何一個**
（ES 的結果是嚴格超集）。原因是 Manticore 的 `ngram_chars` 範圍：

```
ngram_chars = cjk, U+2580..U+25FF, U+2F00..U+A4CF, U+F900..U+FAFF, U+FE30..U+FE4F, U+20000..U+2FA1F
```

多收的字全部落在這些範圍**之外**，Manticore 因此把它們當成分隔符、根本沒進 index，
`exist_in_cbeta` 永遠回 false：

| 類別 | 例子 |
|---|---|
| CJK 擴充 G／H（U+30000 以上） | 𱆮 U+311AE、𱀸 U+31038、𰚖 U+30696 |
| CJK 部首補充（U+2E80..U+2EFF） | ⺩ U+2EA9、⺼ U+2EBC |
| 圈號與符號（U+2460..U+24FF、U+2600..U+267F） | ⑫ U+246B、⒉ U+2489、☷ U+2637 |
| 全形標點 | ： U+FF1A |

ES 的 `pattern` tokenizer 保留所有非空白字元，所以查得到。這些字確實出現在
CBETA 正文裡（`exist?` 查的就是同一份 text.xml），因此**新的結果比較正確** ——
`/search/variants` 會多建議這些寫法，而且建議了就真的搜得到。

## 效能實測（本機 macOS）

| 項目 | 數字 |
|---|---|
| notes index 匯入 | 2,182,414 筆 / 358 秒 / 410MB |
| titles index 匯入 | 4,900 筆 / 0.5 秒 / 0.6MB |
| text index 匯入 | 22,150 卷 / 169 秒 / 1.5GB |
| `rake import:vars` | 56,165 個候選字 / 4.4 秒（改用 `_msearch` 批次前會把 ephemeral port 用光而失敗） |

## 第三期待辦

- [ ] `search/similar`（chunks index）搬到 Elasticsearch。已定案接受 Lucene BM25 與
      Manticore `proximity_bm25` 的排序差異；`search_similar.haml` 的
      「第一階段使用 Manticore 模糊搜尋」屆時要改寫。
- [ ] chunks 搬完後移除：`ManticoreService`、`lib/tasks/manticore/` 的 `conf`／`build`、
      四個 `manticore-template-*.conf`、`section-manticore.rb` 的建資料夾／設定／建 index／
      重啟容器步驟。**`x2t`／`t2x`／`notes`／`titles`／`chunks` 的轉檔部分要留**，
      Elasticsearch 就是吃這些 XML。
- [ ] 屆時 `config.x.se.indexes` 只剩轉檔用途，可一併精簡。
