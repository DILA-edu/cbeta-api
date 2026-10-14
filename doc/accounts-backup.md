# accounts DB 備份到 Firebase

使用者帳號與 API key（accounts DB 的 `users` / `api_keys` / `api_key_usages`）
備份到 Firebase 的 Cloud Firestore。資料量小，但遺失的後果是所有人的 key 立即失效
（見 [api-key-design.md](api-key-design.md) 4.1）。

## 設計摘要

- **平常不讀 Firestore**：API 與網頁的 request 一律讀 server 上的 accounts DB，
  不會等 Firestore。
- **資料變更時才寫入**：`User` / `ApiKey` 有變更時，由 `after_commit` 排入
  `AccountsBackupJob`，約 2 分鐘後推到 Firestore。以 watermark 找出變更的列，
  沒有變更就不寫。
- **每日 cron 保底**：`rake accounts_backup:sync` 每天跑一次，補上遺失的 job。
- **刪除也會同步**：本機刪除的 user，連同他的 key 與使用紀錄，會從 Firestore 刪除。
- **每日 `pg_dump` 保留 7 份**（server 本機）：本機 DB 出問題、錯誤被同步上去時的退路。
- **staging 與 production 寫到不同的 Firestore DB**：設定放 `config/cb.yml` 的
  `firebase_backup`，依 `Rails.env` 區塊各自設定。

### 兩層備份各自防什麼

| 災難 | 用什麼還原 | 最多遺失 |
|---|---|---|
| server 整台掛掉、硬碟壞 | Firestore（`rake accounts_backup:restore`） | 約 2 分鐘；job 遺失時最多 1 天 |
| 本機 DB 被誤刪、清空，錯誤被同步到 Firestore | 本機 `pg_dump` | 1 天 |

server 整台掛掉時 sync 根本不會跑，Firestore 不會被汙染；需要 `pg_dump` 的情況則是
server 還活著。兩種災難不會同時發生，所以 `pg_dump` 放在 server 本機就夠了。

### 為什麼用 `:async` job 而不是 cron 或 Solid Queue

- **不在 request 裡呼叫 Firestore**：登入、建 key 不會變慢，Firestore 出狀況也不影響使用者。
- **`:async` 不需要常駐 worker**：job 在現有的 Passenger process 裡用 thread 執行，
  不佔 Passenger 的 process 名額。Solid Queue 等可靠的 backend 要 staging、production
  各多一個常駐 worker，為這麼少的工作量不划算。
- **代價**：Passenger 關掉 process 時，還沒跑的 job 會遺失、也不會重試。由每日 cron 補上。
- **不用高頻 cron**：變更很少，每幾分鐘一次的 cron 幾乎都在空轉，每輪還要啟動一次 Rails。

job 會延後約 2 分鐘才執行：sync 會略過 1 分鐘內才更新的列（見下方 watermark 細節），
太早跑會看不到剛 commit 的那筆。

### 備份哪些欄位

| 表 | 何時寫入 | 備註 |
|---|---|---|
| `users` | `updated_at` 有變（新登入、email/name 變更、admin 開通） | |
| `api_keys` | `updated_at` 有變（建立、撤銷） | **不含 `last_used_at`** |
| `api_key_usages` | 只推「已結束的日子」，每列只寫一次 | 當天的計數每個 request 都在變，通常由每日 cron 推上去 |

- `last_used_at` 由 `touch_last_used!` 以 `update_column` 寫入、不動 `updated_at`，
  納入的話就無法判斷「有沒有變更」。還原後為空，下次使用就會補上。
- `api_keys` 只存 SHA256 digest 與前綴 hint，**備份裡沒有任何可用的明文 key**。
- `users` 有 email 與名稱（個資），存放在 Google Cloud。

### 安全閥

1. **刪除同步的保險**：「本機沒有就刪」的比對，在本機 DB 出問題時會把備份一起清掉，
   所以：
   - 本機 `users` 是空的 → 不刪，中止。
   - 一次要刪的 user 超過 10 個，或超過本機剩下的 user 數 → 不刪，中止。
     後者是給 user 很少的 staging：DB 重建後只有 1 個新帳號時，10 個的上限擋不住。
     確認是刻意刪除後，用
     `MAX_PRUNE=<數量>` 重跑 `rake accounts_backup:sync`。
   - 只以 user 為單位刪除（key 只會撤銷、不會單獨被刪）；刪 user 時用 `user_id`
     查出他的 key 與使用紀錄一起刪。
   - 擋不住的情況（例如只少了幾個 user）由 `pg_dump` 補救。
2. **環境比對**：每個 Firestore DB 的 `meta/sync` 記錄它屬於哪個 `rails_env`，
   sync / restore 開頭比對 `Rails.env`，不符就中止。防止 cb.yml 抄錯，
   staging 寫進 production 的備份。
3. **DB 重建偵測**：`meta/sync` 記住第一次備份時 id 最小的那筆 user / api_key
   （哨兵）的 `id` 與 `created_at`。PostgreSQL 的 id 不會重複使用，所以本機同一個
   id 的 `created_at` 不同，就代表 accounts DB 被重建過，此時 sync 中止 ——
   否則新的 id 1 號會覆寫備份裡原本的 id 1 號。哨兵被合法刪除（本機沒有該 id）
   則略過，不會誤判。
4. **restore 只寫進空的 DB**，不做合併、不提供強制覆寫。

### watermark 細節

- `users` / `api_keys`：推 `watermark < updated_at <= 現在 - 1 分鐘` 的列。
  留 1 分鐘是為了不漏掉「`updated_at` 已決定、但 transaction 還沒 commit」的列。
- 沒推任何列時不更新 watermark；中途失敗時 watermark 不前進，下次重跑會再 upsert
  一次（結果相同）。
- 單次最多 500 筆一個 commit，資料量大時（例如第一次 sync）會分多個 commit。

## Firestore 上的結構

| collection | document id | 內容 |
|---|---|---|
| `users` | `users.id` | 見上表 |
| `api_keys` | `api_keys.id` | |
| `api_key_usages` | `api_key_usages.id` | `used_on` 存成 `YYYY-MM-DD` 字串 |
| `meta` | `sync` | `rails_env`、watermark、哨兵列的 id 與 `created_at`、`synced_at` |

## 建置（每個環境一次）

建議 **staging 與 production 各開一個 Firebase project**，各自一個 service account。
這樣 staging 的金鑰在權限上就寫不到 production。
（同一個 project 開兩個 named database 也可以，`database_id` 設成該 DB 名稱即可，
但兩個環境的 service account 權限要另外用 IAM condition 隔開。）

1. Firebase console 建 project，進入 **Cloud Firestore** 按「建立資料庫」：
   - 版本選 **Standard**（Enterprise 是 MongoDB 相容版，用不到）
   - 資料庫 ID 保持 **`(default)`**（cb.yml 就不必寫 `database_id`）
   - 位置選離 server 近的，例如 **`asia-east1`（台灣）**。**建立後不能改**
   - 安全性規則選 **「以正式版模式啟動」**（不要選測試模式，它會開放讀寫 30 天）

   Spark 免費方案即可，資料量遠低於免費額度。
2. Security rules 維持「全部拒絕」（正式版模式的預設值就是這樣）：

   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} { allow read, write: if false; }
     }
   }
   ```

   service account 走 IAM，不受 rules 限制；rules 只擋 client SDK，
   而這份資料不該被任何 client 讀到。
3. Google Cloud console →「IAM 與管理」→「服務帳戶」→「建立服務帳戶」，
   角色只給 **Cloud Datastore User**（`roles/datastore.user`）。建好後在「金鑰」分頁
   新增 JSON 金鑰並下載。
   - 不要用 Firebase「專案設定 → 服務帳戶」產生的 Admin SDK 金鑰，權限大得多。
   - 若建立金鑰時被組織政策 `iam.disableServiceAccountKeyCreation` 擋住，
     要請組織管理員為這個專案解除。
4. 把 JSON key 放到 server 上**不隨 slot 輪替**的位置，例如 `~/.config/cbeta-api/`
   （目錄 700、檔案 600）。不要放 `shared/config/`：角色 symlink 輪替後會指向
   另一個 slot，金鑰就得跟著搬。Passenger 執行 app 的使用者必須讀得到這個檔案。

   ```sh
   mkdir -p ~/.config/cbeta-api && chmod 700 ~/.config/cbeta-api
   chmod 600 ~/.config/cbeta-api/firebase-staging.json
   ```

   下載到本機的那份，上傳後即刪除。

5. `config/cb.yml`（gitignored，每個 slot 的 `shared/config/` 各一份）加上：

   ```yaml
   production:
     firebase_backup:
       project_id: <production 的 project id>
       credentials: <production 的 JSON key 路徑>
       # database_id: '(default)'   # 用 named database 時才需要
   staging:
     firebase_backup:
       project_id: <staging 的 project id>
       credentials: <staging 的 JSON key 路徑>
   ```

   **每個 slot 的 cb.yml 都要同時有 `production:` 與 `staging:` 兩個區塊**，
   跟 `database.yml` 的 accounts 設定同一個道理：年度輪替切換 `PassengerAppEnv`
   時，備份目標就跟著 `Rails.env` 自動換過去，輪替 checklist 不必多一步。
   cb.yml 沒有 `firebase_backup` 時，備份停用，不影響 boot 與 request。

6. 確認設定（唯讀，第一次會實際連上 Firestore）：

   ```sh
   cd /var/www/cbeta-api-staging/current
   RAILS_ENV=staging /var/www/cbeta-api-staging/shared/asdf-wrapper bundle exec rake accounts_backup:status
   ```

7. 手動跑第一次 sync（會推出全部資料），再跑一次 `status` 確認 watermark。

   `status` 失敗時的判讀：
   - 讀 JSON key 或取 token 時就出錯 → `credentials` 路徑或檔案權限不對
   - HTTP 403 `PERMISSION_DENIED` → service account 角色不對，或 project 選錯
   - HTTP 404 且訊息提到 database → Firestore 還沒建立，或 `database_id` 錯

## 上線後驗證 job 有沒有真的跑

`:async` 的延遲 job 在 Passenger 下能否正常執行，無法在本機驗證。staging 上線後：

1. 在帳號頁產生一把 key（或撤銷一把）。
2. 等 3 分鐘，跑 `rake accounts_backup:status`，看 `synced_at` 有沒有更新。

沒更新代表 job 這條路不通（例如 timer thread 沒有活過 Passenger 的 fork），
此時備份仍由每日 cron 進行，只是延遲變成最多 1 天。

## cron

路徑一律用角色 symlink（`cbeta-api-staging` / `cbeta-api-production`），
年度輪替時 crontab 不必改。

```cron
# 每日保底 sync (推變更、同步刪除、推前一天的 api_key_usages)
15 3 * * * cd /var/www/cbeta-api-staging/current && RAILS_ENV=staging flock -n /tmp/accounts-backup-staging.lock /var/www/cbeta-api-staging/shared/asdf-wrapper bundle exec rake accounts_backup:sync >> /var/www/cbeta-api-staging/shared/log/accounts-backup.log 2>&1
# 每日 pg_dump,保留 7 份 (檔名用星期幾,自動覆蓋)
45 3 * * * /var/www/cbeta-api-staging/current/bin/accounts-db-dump accounts_dev /home/ray/backups/cbeta-accounts staging
```

- production 把上面的 `staging` 換成 `production`、DB 換成 `cb_accounts`。
  **production 目前跑 `main`（4.x），還沒有 accounts DB**，等 API key 功能上
  production 後再加。
- `rake accounts_backup:sync` 沒有變更時不輸出；有寫入時輸出一行摘要；失敗時輸出錯誤並以非 0 結束。
- `bin/accounts-db-dump` 只在失敗時輸出（cron mail 會收到）。它不經過 Rails、直接指名
  DB：`database.yml` 指錯 DB 時，用 Rails 備份也會備到錯的那個。`users` 是空的時候
  拒絕 dump，避免七份好的備份一天一份被空資料蓋掉。
- dump 放在**不隨 slot 輪替**的固定位置（與金鑰同理），staging 與 production
  用檔名前綴區分。
- `pg_dump` 的連線用 `~/.pgpass` 與 `PGUSER` 環境變數（寫在 crontab 開頭：
  `PGUSER=<accounts DB 的 owner>`）。`.pgpass` 的 host 欄位要寫 `127.0.0.1`
  （libpq 逐字比對，script 連的是 `127.0.0.1`），權限必須是 600 ——
  權限太寬時 libpq 會忽略整個檔案，手動執行時改問密碼，cron 裡則直接失敗。
  加 crontab 前先用 `-w`（絕不詢問密碼）模擬 cron 確認：

  ```sh
  PGUSER=<owner> psql -h 127.0.0.1 -d accounts_dev -w -tAc 'SELECT 1'
  ```
- crontab 用 `ray` 自己的 `crontab -e`，**不要加 sudo**：那會變成 root 的 crontab，
  讀不到 `~ray/.pgpass`，產生的檔案擁有者也會是 root。
- 兩個 Passenger app 的 web process 也會在資料變更時自己排 job，不需要另外設定。

## 還原

### 從 Firestore 還原（server 掛掉、DB 遺失）

1. 確認目標 accounts DB 存在且已 migrate、三張表都是空的
   （不是空的會拒絕；要以備份覆蓋時請先自行清空）。
2. 執行：

   ```sh
   cd /var/www/cbeta-api-staging/current
   RAILS_ENV=staging /var/www/cbeta-api-staging/shared/asdf-wrapper bundle exec rake accounts_backup:restore
   ```

3. 還原會保留原本的 id 與時間戳，並重設 PostgreSQL 的 sequence。
   原本的 API key 還原後即可照常使用（備份的是 digest，驗證方式不變）。
4. 遺失的範圍：最後一次成功 sync 之後的變更，以及尚未推上去的 `api_key_usages`
   計數（當天與前一天）。**特別注意這段時間內撤銷的 key 會在還原後恢復有效**；
   若災難發生前剛處理過外流的 key，還原後要再撤銷一次。

### 從 `pg_dump` 還原（本機 DB 出問題，錯誤已同步到 Firestore）

1. 先停掉每日 cron，避免還原途中跑 sync。
2. 選擇要用哪一天的檔案（`<前綴>-<星期幾>.dump`，1 = 星期一），還原：

   ```sh
   pg_restore -h 127.0.0.1 -d accounts_dev --clean --if-exists --no-owner /home/ray/backups/cbeta-accounts/staging-3.dump
   ```

3. 整份重推到 Firestore。還原回來的列 `updated_at` 都比 watermark 舊，
   不加 `FULL=1` 的話，被同步刪掉的資料不會補回去：

   ```sh
   RAILS_ENV=staging FULL=1 /var/www/cbeta-api-staging/shared/asdf-wrapper bundle exec rake accounts_backup:sync
   ```

4. 恢復 cron。dump 之後的變更會遺失（最多 1 天）。

## 為什麼用 REST API 而不是 google-cloud-firestore gem

`google-cloud-firestore` 依賴 `grpc` native extension，新版 Ruby 常常還沒有預編譯版本，
在 server 上要自己編譯。這裡只需要讀單筆、列 collection、單一欄位查詢、批次 upsert 與刪除，
直接打 Firestore REST API（Faraday + `googleauth` 取 token）就夠了。
見 `app/services/accounts_backup/firestore_client.rb`。
