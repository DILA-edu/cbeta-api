# API Key 控管機制設計文件

- 建立日期：2026-08-21
- Branch：`feature/api-key-management`（從 `dev` 開出）
- 狀態：**已實作**（2026-08-21）。VERSION 4.6.0 → 4.7.0。
  尚待處理的事項見第 11 節「待主管回覆／待討論」與下方「實作與設計的差異」。
- 版本：VERSION **4.7.0**（新增功能，過渡期不破壞相容）

## 0. 實作與設計的差異

實作時查證後做的調整，理由都寫在對應 commit 訊息裡：

| 項目 | 設計 | 實作 | 理由 |
|---|---|---|---|
| Origin 白名單位置 | `config/environments/*.rb`，納入版控 | `config/cb.yml`，不進版控 | **2026-08-21 主管指示**（見 3.3） |
| `config/environments/cn.rb` | 評估刪除 | **刪除** | 2026-08-21 確認 `api.cbetaonline.cn` 廢棄不用，`cn` 環境整組退場（7.3） |
| `api_keys` 欄位 | 無前綴欄位 | 多一個 `token_hint` | 5.4 要求帳號頁「只顯示前綴」，但 digest 無法反推前綴（4.3） |
| `ReportController` | 整個 controller 限 admin | `index` 例外開放 | `report#index` 是「字數統計」的欄位說明頁，不含流量資料，且從公開頁面連過去。7.4 本身已預留個別報表開放的空間 |
| `origin_stats` 計數位置 | 塞進 `log_action_start` | 另開 `record_origin` | `log_action_start` 是純 logging；6.4 本身就警告不要動壞它（fail2ban 靠它的 log 格式） |
| rate limit 的 cache store | 另設 Redis | 沿用各環境的 `config.cache_store` | production 的 memcached 與 staging 的 Redis，`increment` 都支援 `expires_in`，不需另設（6.3） |

額外補上的東西（設計未提，實作時認為必要）：

- `rake api_key:config` —— 白名單不進版控後，必須有辦法在機器上查生效設定。
- `rake origin:report[days]` —— 4.5 的埋點若沒有讀取工具就是唯寫資料。
- `rake user:list` / `user:grant_admin` / `user:revoke_admin` —— 4.2 的 admin 開通。
- `doc/annual-rotation.md` —— 7.3 要求的年度輪替 checklist。
- `static_pages/api_key` 說明頁（9）。

---

## 1. 需求摘要

1. 使用者以 Google 或 GitHub 帳號登入，登入成功後可取得 API key。
2. 呼叫 API 時傳送 API key。
3. 懷疑 key 外流時，可撤銷並重新產生。
4. **過渡期**：未帶 key 仍可使用 API；若帶了 key，則必須是有效的 key 才能使用。
5. request 的 Origin 若為 `cbetaonline.dila.edu.tw` 或 `cbetaonline-dev.dila.edu.tw`，例外放行。
   - 已知 Origin 可被偽造（`curl -H "Origin: ..."`），此為主管指示的既定方針。
   - 網頁前端（cbetaonline）**不帶 key** —— 因為前端無法保護 key。key 只發給程式化 client（研究者腳本、第三方 app、server-to-server）。

---

## 2. 現況調查結果（2026-08-21 實機查證）

### 2.1 伺服器拓樸

`cbdata.dila.edu.tw` 與 `sakya.dila.edu.tw` 是**同一台機器**。Apache 設定在
`/etc/apache2/sites-available/cbdata-sub.conf`（由 `cbdata.conf` 與
`cbdata-le-ssl.conf` 以 `Include` 引入）：

| 掛載路徑 | 實體目錄 | PassengerAppEnv | 內容 DB | analytics DB | REDIS_URL |
|---|---|---|---|---|---|
| `/stable` | `/var/www/cbapi1` | production | `cbdata1` | `cb_analytics` | `redis://localhost:6379/1` |
| `/dev` | `/var/www/cbapi2` | staging | `cbdata2` | `analytics_dev` | `redis://localhost:6379/0` |

- 根 vhost（`cbdata.dila.edu.tw/`）的 app 在 `/var/www/cbdata`，最後部署 2025-12-29
  且已無 log 活動，實質停用，僅作為 DocumentRoot 提供靜態檔與上述兩個掛載點。
- `/var/www/cbapi3` 存在但目前未掛載，是下一輪輪替要用的 slot。
- `ApplicationController#record_visit` 會剝除 `/dev`、`/stable`、`/v1.2` 前綴，
  即為配合這套 sub-URI 掛載。

### 2.2 年度輪替（重要背景）

每年 CBETA 資料更新（R1 → R2 → R3 …）時會輪替 app slot：

- 目前：cbapi1 = R1 production，cbapi2 = R2 staging（測試中）。
- R2 測試通過 → cbapi2 成為 production，`dev` branch merge 進 `main`。
- 接著 `dev` 為 R3 做準備，staging 換到 cbapi3。

本 API key 機制預計在 R2 上 production 之後、做 R3 準備時，隨 staging 上到 cbapi3。

### 2.3 Apache 已經在做 CORS（原本未預期）

`cbdata-sub.conf` 的 `/stable` 與 `/dev` 兩個 `<Location>` 內都已設定：

```apache
SetEnvIf Origin "^(https://(cbeta\.org|cbetaonline-dev\.dila\.edu\.tw|cbetaonline\.dila\.edu\.tw|cbetaonline\.cn|docusky\.org\.tw|mrmyhuang\.github\.io|syda\.dila\.edu\.tw)|http://localhost:8000)$" AccessControlAllowOrigin=$0
Header always set Access-Control-Allow-Origin  "%{AccessControlAllowOrigin}e" env=AccessControlAllowOrigin
Header always set Access-Control-Allow-Methods "GET, POST, OPTIONS"
Header always set Access-Control-Allow-Headers "Content-Type, Authorization"
Header always set Vary "Origin"
```

結論：

1. **不需要引入 `rack-cors`**。`Access-Control-Allow-Headers` 已含 `Authorization`，
   `Vary: Origin` 也已設定。再加一層會出現重複 header 的問題。
2. **但 OPTIONS 預檢仍要處理**。Apache 的 `Header always set` 只補回應 header，
   OPTIONS 請求本身會進到 Rails；`config/routes.rb` 的 route 都只註冊
   `via: [:get, :post]`，OPTIONS 會回 404，而預檢必須是 2xx 才通過。
   目前之所以沒問題，是因為既有前端不帶自訂 header（屬簡單請求，不觸發預檢）；
   一旦有 client 帶 `Authorization` 就會遇到。
3. Apache 白名單有 **8 個來源**，比本次要放行的 2 個多出：
   `cbeta.org`、`cbetaonline.cn`、`docusky.org.tw`、`mrmyhuang.github.io`、
   `syda.dila.edu.tw`、`http://localhost:8000`。詳見第 11 節「待主管回覆」。

### 2.4 doorkeeper 實質未使用

- `config/initializers/doorkeeper.rb` 的 `resource_owner_authenticator` 直接回傳
  `Struct.new(:id).new(0)`（假使用者），`skip_authorization { true }` 全部自動放行。
- 唯一引用 `Doorkeeper::Application` 的 `app/controllers/oauth/registrations_controller.rb`，
  其 route 在 `config/routes.rb` 中是註解掉的。
- 當初裝 doorkeeper 純粹為了 `/mcp` 的 OAuth，後來確認 `/mcp` 不需認證就停用了。
- **決策：一併移除，全站只保留一套認證。**

### 2.5 `/mcp` 流量

- 根 vhost 對 `/mcp` 全部回 404（141 筆／兩週），來源皆為掃描器
  （Infrawatch bot、`python-httpx`），可忽略。
- `/stable`（production）的 `production.log` 中 `/mcp` 為 **0 筆**。
- `/dev/mcp` 每天有真實流量（30～360 筆／天），user agent 為 `claude-code`、
  `Claude-User`（來源 IP `160.79.106.x`，Anthropic egress）。
- 經實機驗證：該流量來自 claude.ai 帳號上名為 **CBETA Search** 的 connector。
  **使用者已於 2026-08-21 在 claude.ai 將該 connector disconnect。**
- 機器上另有一個**獨立**的 MCP 服務：Apache vhost `mcp.dila.edu.tw`
  反向代理到 `127.0.0.1:8000`（`/var/www/mcp`），與本 repo 無關。
- **決策：政策上不再由本 app 提供 MCP 服務，`/mcp` 現在就移除。**

### 2.6 已確認無安全問題的項目

- `config/database.yml` 雖含明文密碼，但在 `.gitignore:14`，且 `git log --all` 查無紀錄，
  從未進入版控。本 repo 在 GitHub 為 public，此項無洩漏。

### 2.7 fail2ban 現況（與 rate limit 直接相關）

伺服器上 fail2ban 有兩個相關 jail：

**jail `cbeta-api-r3`**（`/etc/fail2ban/jail.local`）

```
filter   = rails
logpath  = /var/www/cbapi?/shared/log/production.log
maxretry = 45
findtime = 5
bantime  = 3600
```

`filter.d/rails.conf` 的 failregex 是 `^.* Started .* for <ADDR>` ——
它把**每一個 request 都當成一次 failure**，不是在偵測攻擊特徵。
效果等於一個粗糙的 IP 層 rate limiter：任何 IP 在 5 秒內超過 45 個 request
（≈9 req/s，≈540 req/min）就 ban 整個 IP 一小時。

兩個要注意的點：

1. `logpath` 的 glob 只吃 `production.log`。cbapi2 目前跑 staging env、寫 `staging.log`，
   **因此 `/dev` 目前完全沒有 fail2ban 保護**。年度輪替後 cbapi2 轉為 production
   並開始寫 `production.log` 才會被納入。
2. `ignoreip = 172.27.0.0/16 192.168.0.0/16` 只白名單內網。

**jail `apache-4xx-rate`**（`/etc/fail2ban/jail.d/apache-4xx-rate.local`）

```
failregex 只匹配 403 | 404
maxretry  = 60 / findtime = 300
bantime   = 3600，遞增最多 86400
```

**401 與 429 不在其中** → 本設計新增的 401 / 429 不會誤觸這個 jail。

---

## 3. 認證與放行邏輯

### 3.1 key 的傳遞方式

**只接受** HTTP header：

```
Authorization: Bearer <api_key>
```

- 不接受 query param（如 `?api_key=`）。理由：query string 會被寫入 Apache access log、
  Rails log 與 `visits` 統計，等於在多處留下明文 key。
- JSONP（`callback` 參數）client 無法設定 header，但 JSONP 的使用者是網頁前端，
  走 Origin 例外，本來就不需要 key，因此不衝突。
- 日後若確實出現無法設 header 的 client，再另行評估。

### 3.2 放行判斷（過渡期）

判斷順序：

1. **有帶 `Authorization: Bearer`** → 一律驗證。key 無效即回 **401**，
   即使 Origin 命中白名單也一樣。
   - 理由：帶了無效 key 通常是 client 設定錯誤。靜默放行會讓開發者誤以為 key 有效，
     等過渡期結束才一次爆掉。
   - 這也符合原始需求「如果傳送 api key, 就驗證 key 有效才能使用 api」。
2. **未帶 key**：
   - Origin 命中白名單 → 放行。
   - Origin 為 `nil`（JSONP、curl、server-side 呼叫、瀏覽器直接開網址都沒有 Origin）
     或 Origin 不在白名單 → **過渡期放行**；過渡期結束後回 **401**。

| Origin | 帶 key | 過渡期 | 過渡期結束後 |
|---|---|---|---|
| 命中白名單 | 無 | 放行 | 放行 |
| 命中白名單 | 有效 | 放行 | 放行 |
| 命中白名單 | 無效 | **401** | **401** |
| nil 或未命中 | 無 | 放行 | **401** |
| nil 或未命中 | 有效 | 放行 | 放行 |
| nil 或未命中 | 無效 | **401** | **401** |

### 3.3 Origin 白名單

本次只放行 2 個（主管指示）：

```
https://cbetaonline.dila.edu.tw
https://cbetaonline-dev.dila.edu.tw
```

- 比對時只比 Origin 完整字串（scheme + host [+ port]），不做 subdomain 模糊比對。

#### 放在哪裡：**2026-08-21 主管指示改為不進版控**（已推翻原設計）

放 `config/cb.yml`（該檔 gitignored、每台機器一份），各環境用自己的區塊：

```yaml
production:
  api_origin_allowlist:
    - 'https://cbetaonline.dila.edu.tw'
    - 'https://cbetaonline-dev.dila.edu.tw'
staging:
  api_origin_allowlist:
    - ...
```

`config/application.rb` 以 `Array(config.cb.api_origin_allowlist)` 讀入。

原設計主張放 `config/environments/*.rb` 納入版控，理由是：白名單屬安全設定，
放版控才能 review 與追歷史；且白名單本非機密（任何人開 cbetaonline 用 DevTools
即可看到 Origin；更直接的是伺服器會把命中的 Origin echo 回
`Access-Control-Allow-Origin`，可用探測法列舉；且 Origin 本身可任意偽造，
保密與否對防偽造毫無差別 —— Kerckhoffs 原則）。

**主管於 2026-08-21 指示不進版控，依指示辦理。**

因此原設計靠 code review 擋住的風險改用以下方式補償：

1. `rake api_key:config` 印出生效的白名單、過渡期開關與額度。
   **每台機器部署後、以及過渡期結束前，都要跑這個確認。**
2. `test/lib/api_origin_allowlist_config_test.rb` 測試 cb.yml → config 的接線，
   避免接錯時靜默變成空陣列。
3. ⚠️ 新機器（或年度輪替的新 slot）的 `shared/config/cb.yml` **必須補上這個 key**。
   漏了在過渡期內不會有症狀（未帶 key 照樣放行），但 `api_key_required` 一改成
   `true` 就會讓 cbetaonline 前端**全站 401**。輪替 checklist 見
   `doc/annual-rotation.md`。

### 3.4 錯誤回應

- key 無效 / 過渡期結束後未帶 key → HTTP **401**，並帶
  `WWW-Authenticate: Bearer realm="CBETA API"`（RFC 6750）。
- rate limit 超限 → HTTP **429**，並帶 `Retry-After`。
- body 沿用現有格式：`{ "error": { "code": 401, "message": "..." } }`。
- 注意：現有 `ApplicationController#my_render_error` **沒有帶 HTTP status**（回 200）。
  新的 401/429 不要走該 method；也不要在本 branch 修改它的行為（會影響既有 client）。
- JSONP 情況下 client 讀不到 HTTP status，錯誤回應仍需支援 `callback` 包裝。
- 過渡期未帶 key 而放行時，於回應加上提示 header，讓 client 開發者能提早發現：
  `X-CBETA-API-Key: recommended`（過渡期結束後將強制要求）。
  這比只在網站公告有效。

### 3.5 納管範圍（allowlist，非全站套用）

採 **allowlist**：新增 concern，由需要納管的 controller 明確 `include`。
漏掉的後果是「該 endpoint 沒納管」，而不是「意外擋掉不該擋的東西」——
語意比 denylist 安全。

**納管**（API）：
`api/*`（collections / resources / sections）、`v1/tools/*`、`search*`、`juans*`、
`lines`、`works*`、`toc`、`toc_node`、`catalog_entry`、`changes`、
`chinese_tools/sc2tc`、`export/*`、`word_seg*`、`textref/*`、`category/:category`、
`kwic3`

**不納管**：
- `/health`、`/openapi.json`
- `static_pages/*`（HTML 說明文件）
- `/download`（靜態檔）
- 登入與帳號管理頁（`/auth/*`、`/account/*`）
- `report/*` —— 不納管 API key，但改為**限管理者**（見 7.4）

---

## 4. 資料模型

### 4.1 新增第三個資料庫：`accounts`

primary（內容）DB 每年隨 CBETA 資料更新全部清掉重建 2～3 次，**使用者資料絕對不能放
primary**。也不放 analytics —— 語意不符，且備份策略不同：analytics 掉了可以重跑統計，
users / api_keys 掉了所有人的 key 立即失效，需要更嚴格的備份。

`config/database.yml` 各環境新增 `accounts` 區塊（沿用現有命名慣例）：

| 環境 | accounts DB |
|---|---|
| production | `cb_accounts` |
| staging | `accounts_dev` |
| development | `db/development-accounts.sqlite3` |
| test | `db/test-accounts.sqlite3` |

- `migrations_paths: db/accounts_migrate`
- 新增 `app/models/accounts_record.rb`（`abstract_class`，`connects_to database: { writing: :accounts }`），
  users / api_keys / api_key_usages 皆繼承它。
- **年度輪替不需搬移使用者資料**：內容 DB 隨輪替換（cbdata1→2→3），accounts DB 固定。
  做法是每個 slot 的 `shared/config/database.yml` 中，`production:` 區塊的 accounts 指
  `cb_accounts`、`staging:` 區塊指 `accounts_dev`；切換 `PassengerAppEnv` 時自動換過去，
  輪替 checklist 不必多一步。附帶效果：staging 測試期間產生的帳號留在 `accounts_dev`，
  不會汙染 production。

### 4.2 `users`

```ruby
create_table :users do |t|
  t.string  :provider, null: false   # "google_oauth2" | "github"
  t.string  :uid,      null: false
  t.string  :email
  t.string  :name
  t.boolean :admin, null: false, default: false
  t.timestamps
end
add_index :users, [:provider, :uid], unique: true
add_index :users, :email
```

- identity 以 `provider` + `uid` 為準，**email 僅作參考**（GitHub email 可能為 private 或 nil）。
- 同一人用 Google 與 GitHub 分別登入 → 視為兩個獨立帳號，不自動合併。
- 收集 email 的目的：必要時能聯絡對方（例如 key 異常使用、服務變更通知）。
  需在登入頁與帳號頁做隱私權告知。
- `admin` 首批以 rake task 依 email 指定開通。

### 4.3 `api_keys`

```ruby
create_table :api_keys do |t|
  t.references :user, null: false
  t.string   :token_digest, null: false
  t.datetime :last_used_at
  t.datetime :revoked_at
  t.timestamps
end
add_index :api_keys, :token_digest, unique: true
add_index :api_keys, [:user_id, :revoked_at]
```

- **不存明文**。只存 `Digest::SHA256.hexdigest(token)`；明文僅在產生當下顯示一次。
- key 格式：`cbeta_` + `SecureRandom.urlsafe_base64(32)`。加前綴便於辨識，
  也有利於 secret scanning 工具偵測。
- 有效 = `revoked_at.nil?`。**撤銷用軟刪除**（設 `revoked_at`），保留稽核紀錄，不硬刪。
- 每個 user 同時最多 **2 把**有效 key，於 model validation 檢查
  （`where(user_id:, revoked_at: nil).count < 2`）。
  目的是支援無縫 rotation：先建新 key → 換完 → 再撤銷舊 key。
- **不設 expiry、不設備註名稱**（本次範圍外）。
- **不使用 Redis cache**。理由：
  - 驗證是 `token_digest` unique index 的單筆查詢，PostgreSQL 微秒級；而每個 request
    本來就已經寫一筆 `record_visit` 的 INSERT，寫入遠比讀取貴，多一個 SELECT 不是瓶頸。
  - 加 cache 就必須處理撤銷失效；「刪了還能用幾分鐘」對「懷疑外流要立刻止血」
    這個核心需求是直接的功能缺陷。
- `last_used_at` 需節流：距上次更新超過 **1 小時**才寫，並用 `update_column`
  跳過 callback 與 validation。

### 4.4 `api_key_usages`

同時記 user 與 key 兩個維度。key 會輪替，只記 per-key 會在 rotation 時斷掉；
但要追查「哪把 key 外流」又必須知道是哪把 key。一張表兩個 id，成本相同、彈性最大。

```ruby
create_table :api_key_usages do |t|
  t.references :user,    null: false
  t.references :api_key, null: false
  t.date       :used_on, null: false
  t.integer    :count,   null: false, default: 0
end
add_index :api_key_usages, [:api_key_id, :used_on], unique: true
add_index :api_key_usages, [:user_id, :used_on]
```

- 寫入用 `INSERT ... ON CONFLICT DO UPDATE count = count + 1`，
  與現有 `ApplicationController#record_visit` 同一個模式。
- 只在「有帶 key」時記錄。
- 放 accounts DB（與 users 同庫，可直接 join；量小，per-user per-day 一列）。

### 4.5 `origin_stats`（過渡期埋點）

過渡期結束時，若 cbetaonline 前端實際上沒送 Origin，前端會全站掛掉。
需在過渡期就蒐證，不必等前端工程師回覆。

```ruby
create_table :origin_stats do |t|
  t.string  :origin, null: false   # nil 記為 "(none)"
  t.date    :used_on, null: false
  t.integer :count, null: false, default: 0
end
add_index :origin_stats, [:origin, :used_on], unique: true
```

- 放 **analytics DB**（純統計、量小、不需 join users）。
- `ApplicationController#log_action_start` 已經在記 origin，加一筆計數即可，成本極低。
- 用途：觀察 cbetaonline 的流量是落在「命中白名單」還是「Origin 為 nil」。
  若全部落在 nil，即可提前確認過渡期結束會出事。

---

## 5. 登入（OmniAuth）

### 5.1 gem

```ruby
gem 'omniauth'
gem 'omniauth-google-oauth2'
gem 'omniauth-github'
gem 'omniauth-rails_csrf_protection'   # 必裝，否則有 login CSRF 漏洞
```

### 5.2 CSRF 與 controller 分層（重要）

現況 `ApplicationController` 有 `skip_before_action :verify_authenticity_token`
（**全站關閉 CSRF**，因為 API 回傳 JSON 需要 callback）。

OAuth 登入流程、以及「撤銷／重新產生 key」這些會改變狀態的操作，**絕對不能**
在關閉 CSRF 的 controller 下進行。

- 新增 `app/controllers/web_controller.rb`（`< ActionController::Base`）作為 web 端 base：
  開啟 session、**開啟 CSRF**、不做 `record_visit`。
- 登入（`SessionsController`）、帳號與 key 管理（`AccountsController` / `ApiKeysController`）、
  以及 `ReportController` 都改繼承 `WebController`。
- API 端維持 stateless，繼承現有 `ApplicationController`。

### 5.3 設定

- Google / GitHub 的 client id 與 secret 放 **Rails credentials**
  （`master.key` 已是 linked file），**不進版控**。
- callback URL 需分別註冊各環境的網址（注意 sub-URI 前綴）：
  - production：`https://cbdata.dila.edu.tw/stable/auth/:provider/callback`
  - staging：`https://cbdata.dila.edu.tw/dev/auth/:provider/callback`
- session 目前是 `cookie_store`（`config/initializers/session_store.rb`），沿用即可。

### 5.4 頁面

- 登入頁：說明用途、隱私權告知（會保存 provider/uid/email/name 及用途）。
- 帳號頁：
  - 顯示目前有效的 key（只顯示前綴與建立時間、`last_used_at`，不顯示明文）
  - 「產生新 key」（明文只在此顯示一次，並提示複製後不再顯示）
  - 「撤銷」
  - **自己的使用統計**（每日次數、各 key 的 `last_used_at`）
    —— 這對「懷疑外流」很關鍵：使用者看到 `last_used_at` 是自己沒在用的時間，
    才會知道該撤銷。所以自己的統計必須讓使用者看得到。

---

## 6. Rate limit（與 fail2ban 分工）

「api key 控管」若沒有配額，key 只是身分標籤。且過渡期「未帶 key 就放行」意味著
防護等於零：濫用者只要不帶 key 就完全不受限，正常使用者反而要多做事，
沒有任何動機申請 key。

### 6.1 分工原則

fail2ban 與 Rails rate limit **不需要數字一致，而是分層負責**：

| 層 | 負責 | 手段 |
|---|---|---|
| fail2ban | IP 層、無狀態的粗暴流量 | iptables 擋掉，request 不進 Rails，最省資源 |
| Rails `rate_limit` | 有身分的配額 | 回 429 + `Retry-After`，讓 client 知道要退讓 |

### 6.2 額度設計（已依 fail2ban 現況調整）

- **未帶 key**：60 requests / minute / IP
- **有帶有效 key**：300 requests / minute / user

**為什麼是 300 而不是原先設想的 600**：`cbeta-api-r3` jail 的實際上限是
≈540 req/min，且懲罰是 **ban 整個 IP 一小時**，遠比 429 粗暴。若 Rails 的
per-user 上限訂在 600，等於永遠打不到，有效上限變成 fail2ban 那條 ——
「有 key 享有較高額度」就失去意義，而且使用者會被整段 ban 掉而不是收到 429。

把 Rails 上限訂在 fail2ban 之下，429 會先發生，fail2ban 退居最後一道防線。
這樣不必修改 fail2ban 設定，是成本最低的做法。

（另一條路是讓 `cbeta-api-r3` jail 能區分帶 key 的 request，但那需要改
filter 與 Rails log 格式，複雜度不划算。）

### 6.3 實作

- 用 Rails 8 內建 `rate_limit`（`ActionController::RateLimiting`），需要 cache store。
- cache store 用 Redis：`REDIS_URL` 已由 Apache 提供（stable `/1`、dev `/0`），
  `redis` gem 已在 Gemfile。

### 6.4 ⚠️ 不可破壞 fail2ban 的 log 來源

`app/controllers/application_controller.rb` 中 `log_action_start` 的註解
`# warn level log for fail2ban` 指的就是 `cbeta-api-r3` jail。

實作時若重構 `log_action_start`，Rails 內建的 `Started ... for <IP>` 這行
**格式必須保留**，否則 jail 會靜默失效（不會有任何錯誤訊息，只是不再 ban 任何人）。

### 6.5 建議但可延後：為 401 連續失敗新增 jail

目前 401 不在 `apache-4xx-rate` 的匹配範圍，而 `cbeta-api-r3` 是按總流量計算、
與成敗無關 —— 也就是說**暴力猜 key 不會被 ban**。

猜中 key 在數學上不可行（32 bytes 隨機），所以不急迫；但較穩健的做法是仿 SSH：
Rails 在 key 驗證失敗時寫一行固定格式的 warn log，新增一個 filter 抓它，
maxretry 設低（例如 10 次 / 10 分鐘）。這也能阻擋拿洩漏的舊 key 清單來掃的行為。

列為建議事項，可在主體功能上線後再做。

## 7. 一併移除的項目

### 7.1 doorkeeper（commit 1）

- Gemfile 移除 `gem 'doorkeeper'`
- 刪除 `config/initializers/doorkeeper.rb`
- `config/routes.rb` 移除 `use_doorkeeper` 區塊與相關註解、被註解掉的 OAuth route
- 刪除 `app/controllers/oauth/registrations_controller.rb`
- `config/initializers/assets.rb:12` 移除 `doorkeeper/application.css` precompile
- 新增 migration：drop `oauth_access_grants`、`oauth_access_tokens`、`oauth_applications`
- 刪除 `app/controllers/well_known_controller.rb` 與相關 route（僅為 OAuth discovery 而存在，
  實作時確認無其他用途）

### 7.2 `/mcp`（commit 2）

- 刪除 `app/controllers/mcp_controller.rb`
- 刪除 `app/services/mcp/`（整個目錄，11 個檔）
- 刪除 `test/integration/mcp_test.rb`、`test/services/mcp/`
- `config/routes.rb` 移除 `/mcp` route
- 刪除 `doc/mcp.md`
- **`/v1/tools/*` 不受影響** —— 那是 `public/openapi.json` 記載的公開介面，
  `/mcp` 只是包一層。`app/services/mcp/*_tool.rb` 是 dispatch 到 `V1::*Controller`，
  反向沒有依賴。
- `app/controllers/concerns/tool_envelope.rb` 保留（`V1::ToolsController` 在用）。

### 7.3 deploy 設定重整（commit 3）

**問題**：目前 deploy target 名稱與實際環境對不上，且每年輪替要手改
`deploy_to`，Apache 的 `Define stable_path` / `dev_path` 也要同步改，兩處容易不一致。

現況：

| 檔案 | deploy_to | 實際上是 |
|---|---|---|
| `config/deploy/sakya.rb` | `/var/www/cbapi1` | **production** |
| `config/deploy/production.rb` | `/var/www/cbapi2` | staging |
| `config/deploy/staging.rb` | `/var/www/cbapi2` | staging（與上面完全相同）|

**解法：用 symlink 把「角色」與「slot」解耦。**

在伺服器上建立兩個角色 symlink：

```bash
ln -sfn /var/www/cbapi2 /var/www/cbeta-api-production   # 年度輪替只改這兩條
ln -sfn /var/www/cbapi3 /var/www/cbeta-api-staging
```

版控裡的設定永遠寫角色路徑，不寫 slot 編號：

```ruby
# config/deploy.rb（共用，設一次）
set :application, 'cbeta-api'

# config/deploy/production.rb
server 'sakya.dila.edu.tw', user: 'ray', roles: %w{app db web}
set :deploy_to, '/var/www/cbeta-api-production'

# config/deploy/staging.rb
server 'sakya.dila.edu.tw', user: 'ray', roles: %w{app db web}
set :deploy_to, '/var/www/cbeta-api-staging'
```

**`set :application` 不需依環境區分，且應移到 `config/deploy.rb`。** 理由：

- 它在本專案中**完全沒有被使用** —— `config/`、`lib/`、`Capfile` 裡沒有任何
  `fetch(:application)`。Capistrano 只在未設定 `deploy_to` 時用它推導預設路徑
  （`/var/www/#{application}`），而兩支 stage 檔都明確設了 `deploy_to`。
- 目前兩支都寫 `'cbapi2'`（slot 編號）。改用角色 symlink 後這個值會變成誤導：
  明年 production 是 cbapi3，但檔案裡還寫 cbapi2，而且因為它不影響部署結果，
  沒人會記得改。
- 「應用程式的名字」本來就不隨環境變化，放共用檔才合語意；環境的區分已由
  stage 名稱（`cap production deploy` / `cap staging deploy`）與 `deploy_to` 表達，
  不需要第三個地方重複。

```apache
# cbdata-sub.conf（伺服器上手動改，非版控）
Define stable_path /var/www/cbeta-api-production
Define dev_path    /var/www/cbeta-api-staging
```

年度輪替流程簡化為：改兩條 symlink → `systemctl reload apache2`。
**版控裡的檔案一行都不用動**，也不會有兩處不同步的問題。

注意事項：
- Capistrano 的 `deploy_to` 指向 symlink 完全正常（`releases/`、`shared/` 都在實體目錄內）。
- Passenger 會 resolve realpath，改 symlink 後需 restart；輪替本來就會 restart。
- `PassengerAppGroupName` 目前寫死 `cbdata_stable` / `cbdata_dev`，**維持不變** ——
  名稱跟著角色而非 slot，本來就是對的。
- 代價：「現在誰是 production」在版控裡看不到。因此要
  (a) 加一支 cap task 印出 `readlink -f`，(b) 在 `doc/` 放一份年度輪替 checklist。

同時要做的清理（已全部完成）：
- 刪除 `config/deploy/sakya.rb`、`config/deploy/cn.rb`
- Gemfile 的 `group :production, :cn` 改為 `group :production`
- 刪除 `config/environments/cn.rb` —— 2026-08-21 確認 `api.cbetaonline.cn`
  廢棄不用，`cn` 環境整組退場：另一併移除 `doc/cn.md`、
  `test_remote` 的 `cn` target、`lib/tasks/quarterly` 的 `cn` 分支。
- **不要動** `filter_cn?` / `referer_cn?` 邏輯（`app/controllers/application_controller.rb`）
  與 `config.cn_filter`（`config/application.rb:31`）—— 那是判斷來源 referer 是否
  `.cn` 結尾以決定內容過濾，與部署環境無關，主站仍需要。
- 更新 `doc/deploy-rails-project.md`、`doc/apache2.md`（若有提到 slot 路徑）

### 7.4 report 限管理者（commit 4）

`ReportController` 揭露全站流量與 referer 明細（`Visit.group(:url, :referer)`），
等於公開「誰在用、從哪來」；且為全表 group by sum，本身也是施力點。

- `ReportController` 改繼承 `WebController`，加 `before_action :require_admin!`。
- 未登入 → 導向登入頁；已登入非 admin → 403。
- 全站統計限 admin；**使用者自己的統計不在此限**（在帳號頁，見 5.4）。
- 需告知：現在不用登入就能看報表的人，之後需要登入。
- 若日後有個別報表要開放給非管理者，屆時針對該報表處理，不必全部適用。

---

## 8. CORS / OPTIONS 預檢

- **不引入 `rack-cors`**（理由見 2.3）。
- 在 `config/routes.rb` 加一條 catch-all OPTIONS route，回 **204 No Content**，
  讓預檢能通過。CORS 的回應 header 由 Apache 提供。
- 實作後需實測：從 `cbetaonline-dev.dila.edu.tw` 用 `fetch` 帶
  `Authorization` header 呼叫 API，確認預檢通過且回應可讀。

---

## 9. 文件與版本

- `public/openapi.json`：
  - 加 `securitySchemes.bearerAuth`（`type: http`, `scheme: bearer`）
  - 標註為 optional（過渡期），並在 description 說明未來將強制
  - 同步 `info.version` → `4.7.0`
- `VERSION` → `4.7.0`
- 說明頁（`static_pages`）新增 API key 使用說明。
  **公告時程等主管與同仁討論確定後再加。**
- `test_remote/` 的遠端測試若打到已納管的環境，需帶 key（過渡期內不影響）。

---

## 10. 實作順序（commit 拆分）—— 已完成

實際的 commit（`16f60d9` 之後，新到舊）：

| commit | 內容 | 對應章節 |
|---|---|---|
| `96dd205` | Origin 白名單改放 `config/cb.yml`，不進版控 | 3.3（主管指示） |
| `5543002` | openapi.json 加 bearerAuth、VERSION 4.7.0、說明頁 | 9 |
| `7b0b396` | OPTIONS 預檢 route，回 204 | 2.3、8 |
| `351cd2f` | `origin_stats` 過渡期埋點 | 4.5 |
| `2de6d93` | rate limit（60/min/IP、300/min/user） | 6 |
| `f1a78cf` | API 端驗證 concern + Origin 白名單 + 401 | 3 |
| `a5a51e8` | 流量報表限管理者 | 7.4 |
| `0e99fc2` | OmniAuth 登入 + 帳號頁與 key 管理 | 5 |
| `97bbba2` | accounts DB 與 users / api_keys / api_key_usages | 4.1~4.4 |
| `33fc1a2` | deploy 設定重整（角色 symlink） | 7.3 |
| `8454cdc` | 移除 `/mcp` | 7.2 |
| `f3346de` | 移除 doorkeeper | 7.1 |

`bin/rails test`：215 runs, 777 assertions, 0 failures, 0 errors。

原計畫的 5.2 與 5.3 合併為一個 commit（`0e99fc2`）—— 登入頁若沒有帳號頁可去，
`SessionsController` 就沒有可導向的目標，兩者無法各自獨立運作。

## 10.1 上線前尚待實機驗證

以下是這個 branch 無法在 local 驗證、必須在伺服器上做的事：

1. **Google / GitHub 的 OAuth credentials**（5.3）。
   `bin/rails credentials:edit` 填入 `google:` / `github:` 的
   `client_id` 與 `client_secret`，並在兩邊的 console 註冊各環境的 callback URL
   （注意 sub-URI 前綴）。**這是登入能不能用的前提。**
2. **`shared/config/cb.yml` 補上 `api_origin_allowlist`**（3.3）。
   部署後跑 `rake api_key:config` 確認。
3. **accounts DB 建立**：`cb_accounts`（production）、`accounts_dev`（staging），
   並在 `shared/config/database.yml` 補 `accounts:` 區塊，然後
   `RAILS_ENV=... rake db:migrate`。
4. **CORS 預檢實測**（8）：從 `cbetaonline-dev.dila.edu.tw` 用 `fetch` 帶
   `Authorization` header 呼叫 API，確認預檢通過且回應可讀。
5. **rate limit 實測**：production 的 cache store 是 memcached、staging 是 Redis。
   確認 429 真的會發生（若 cache store 掛了，`increment` 回 `nil`，
   rate limit 會**靜默失效**）。
6. **角色 symlink 建立**（7.3）：
   `ln -sfn /var/www/cbapi? /var/www/cbeta-api-production` 等兩條，
   並同步 Apache 的 `Define stable_path` / `dev_path`。見 `doc/annual-rotation.md`。
7. **首批 admin 開通**：`rake user:grant_admin[email]`（該人需先登入過一次）。
8. **過渡期埋點判讀**（4.5）：上線一段時間後跑 `rake origin:report[30]`，
   確認 cbetaonline 的流量是落在白名單還是 `(none)`。**這是決定過渡期能不能結束的依據。**

---

## 11. 待主管回覆／待討論

1. **其餘 5 個 Origin 的處理**（已詢問主管，等回覆）。
   Apache 白名單另含 `cbeta.org`、`cbetaonline.cn`、`docusky.org.tw`、
   `mrmyhuang.github.io`、`syda.dila.edu.tw`、`http://localhost:8000`。
   本次 Rails 只放行 cbetaonline 兩個站，因此過渡期結束後這 5 個站台會拿到 401
   （CORS 過得了，但沒有 key）。
   而它們看起來都是**純網頁前端**（`mrmyhuang.github.io` 尤其確定），要求它們申請 key
   等於要求把 key 公開寫在 JS 裡 —— 正是本設計一開始就否決的做法。
   實務上這 5 個站台只有三條路：加進 Origin 白名單、自己架後端代理、或斷掉。
   **需在過渡期結束前定案**，否則會有 5 個合作單位同時受影響。
   白名單實作為 config 陣列，日後增減是改一行。
2. **過渡期時程**（待與主管、同仁討論）。需明訂結束條件與日期，避免永久停在過渡期。
3. **rate limit 具體數字**（建議起始值見第 6 節）。
4. **`mcp.dila.edu.tw` 那個獨立 MCP 服務是否提供同樣 10 個工具**
   —— 若沒有，移除本 repo 的 `/mcp` 就是單純失去該能力。
   （使用者已 disconnect claude.ai 上的 connector，移除本身不再有中斷風險。）

---

## 12. 設計上刻意不做的事（與理由）

| 項目 | 理由 |
|---|---|
| 不用 Redis cache 驗 key | 撤銷要能立刻生效；DB 單筆查詢不是瓶頸（4.3） |
| 不引入 rack-cors | Apache 已完整處理 CORS，兩層會重複設 header（2.3） |
| 不接受 query param 傳 key | 會在 access log / Rails log / visits 留下明文（3.1） |
| 不設 key expiry、不設備註名稱 | 本次範圍外，需求未提出（4.3） |
| 不自動合併 Google/GitHub 同 email 帳號 | GitHub email 可能 private 或 nil，不可靠（4.2） |
| 不修改 `my_render_error` | 會改變既有 client 看到的 HTTP status（3.4） |
| 不動 `filter_cn?` / `referer_cn?` | 判斷 referer 是否 `.cn`，與部署環境無關（7.3） |
| ~~Origin 白名單納入版控~~ | **已推翻**：2026-08-21 主管指示不進版控，改放 `config/cb.yml`（3.3） |
| 不修改 fail2ban 設定 | 改 Rails 上限即可讓 429 先於 ban 發生，成本最低（6.2） |
| 不依環境區分 `set :application` | 專案中無任何 `fetch(:application)`，寫 slot 編號只會過期誤導（7.3） |
