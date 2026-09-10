# Elasticsearch 部署（sakya）

搜尋後端的 text / notes / titles 三個 index 由 Manticore 改為 Elasticsearch，
背景與決策見 [elasticsearch-migration.md](elasticsearch-migration.md)。
只剩 chunks（`search/similar`）仍走 Manticore。

**staging 與 production 是同一台機器**（`sakya.dila.edu.tw`，只有 `deploy_to` 目錄不同），
因此共用同一個 Elasticsearch 服務，靠不同的 **index alias** 隔離。

## 伺服器現況（2026-09-08 實測）

| 項目 | 現況 | Elasticsearch 需要 |
|---|---|---|
| CPU | 10 核 | 匯入時約 15 分鐘（排在季度批次流程） |
| 記憶體 | 94GB，實際使用 5.7GB（Manticore 佔 7.45GB） | heap 4GB |
| 匯入 | — | 三個 index 合計約 15 分鐘 |
| 磁碟 | 1TB，使用 44%（剩 544GB） | 三個 index 合計約 1.8GB |
| port | Manticore 用 9307 | 9200（未被佔用） |
| `vm.max_map_count` | 1048576 | ≥ 262144（已滿足，見 `/etc/sysctl.d/10-map-count.conf`） |
| docker | 28.1.1 / compose v2.35.1 | — |

## 與 Manticore 的三個差異

1. **不需要 slot 輪替目錄**。Manticore 每季要新建 `/var/lib/manticoreN`、改 conf、restart 容器；
   Elasticsearch 只要建新的版本化 index 再切 alias，容器完全不動。
2. **容器不需要掛 `/var/www`**。Manticore 的 `xmlpipe_command` 要自己 `cat` text.xml；
   Elasticsearch 是由 Rails 讀檔後透過 HTTP bulk 送進去。
3. **port 只綁 `127.0.0.1`**。Manticore 目前綁 `0.0.0.0:9307`（compose 註解寫明「允許 server
   外連線」），但 Elasticsearch 這裡關掉了 `xpack.security`，**不可對外曝露**。

## 1. compose.yaml

放在 `/home/ray/cbeta-es/compose.yaml`（沿用 Manticore 的慣例：一個服務一個目錄）。

```yaml
# CBETA API 的 Elasticsearch。
# staging 與 production 共用這一個服務，靠不同的 index alias 隔離
# （見 shared/config/cb.yml 的 elasticsearch.index_alias）。
name: cbeta-es

services:
  cbeta-es:
    container_name: cbeta-es
    image: docker.elastic.co/elasticsearch/elasticsearch:9.4.2
    environment:
      - discovery.type=single-node
      # 只綁 127.0.0.1、不對外，因此關閉安全性功能
      - xpack.security.enabled=false
      # 避免 heap 被 swap 出去（server 有 4GB swap）
      - bootstrap.memory_lock=true
      # 三個 index 合計約 1.8GB，4g heap 相當充裕
      - ES_JAVA_OPTS=-Xms4g -Xmx4g
      - TZ=Asia/Taipei
    # 換 index 是靠 alias、不必重啟容器，所以可以放心自動重啟
    restart: unless-stopped
    ports:
      # 一定只綁 127.0.0.1：xpack.security 是關閉的
      - 127.0.0.1:9200:9200
    # heap 4g 加上 Lucene 的 page cache；設上限以免影響 PostgreSQL 與 Manticore
    mem_limit: 8g
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65535
        hard: 65535
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
      - /var/lib/cbeta-es/data:/usr/share/elasticsearch/data
      - /var/log/cbeta-es:/usr/share/elasticsearch/logs
```

## 2. 建立目錄並啟動

Elasticsearch 容器內以 uid 1000 執行，host 目錄要先給對權限。

只有頭兩行需要 `sudo`（`/var/lib` 與 `/var/log` 屬於 root），而且 sakya 的 `sudo` 會要密碼。
**docker 指令不需要 sudo** —— `ray` 已在 `docker` group（現有的 Manticore 流程也是這樣，
見 `lib/tasks/quarterly/section-manticore.rb` 的 `docker compose ... restart`）。

```sh
# 需要 sudo（會要密碼）
sudo mkdir -p /var/lib/cbeta-es/data /var/log/cbeta-es
sudo chown -R 1000:0 /var/lib/cbeta-es /var/log/cbeta-es

# 以下都不需要 sudo
mkdir -p /home/ray/cbeta-es
# 把上面的 compose.yaml 存成 /home/ray/cbeta-es/compose.yaml

docker compose -f /home/ray/cbeta-es/compose.yaml up -d
```

確認服務（`status` 應為 `green`）：

```sh
curl -fsS http://localhost:9200
curl -fsS 'http://localhost:9200/_cluster/health?pretty'
docker logs --tail 30 cbeta-es
```

確認**沒有**對外開啟：

```sh
ss -tlnp | grep 9200   # 應該只看到 127.0.0.1:9200
```

## 3. cb.yml 設定片段

`config/cb.yml` 是 capistrano 的 linked file，每個 deploy 各一份、不進版控：

* staging：`/var/www/cbeta-api-staging/shared/config/cb.yml`
* production：`/var/www/cbeta-api-production/shared/config/cb.yml`

在各自檔案的環境區塊**加上** `elasticsearch:`（其餘既有設定保留不動）。

staging：

```yaml
staging:
  api_origin_allowlist:
    - 'https://cbetaonline.dila.edu.tw'
    - 'https://cbetaonline-dev.dila.edu.tw'
  # ↓ 新增
  elasticsearch:
    url: 'http://localhost:9200'
    # 與 production 共用同一個 ES 服務，一定要用不同的 alias
    index_alias: 'cbeta_text_staging'
```

production：

```yaml
production:
  api_origin_allowlist:
    - 'https://cbetaonline.dila.edu.tw'
    - 'https://cbetaonline-dev.dila.edu.tw'
  # ↓ 新增
  elasticsearch:
    url: 'http://localhost:9200'
    index_alias: 'cbeta_text_current'
```

可用的 key：

| key | 預設 | 說明 |
|---|---|---|
| `url` | `http://localhost:9200` | Elasticsearch 位址 |
| `index_alias` | `cbeta_text_current` | **text** index 的 alias，同時也是其他 alias 的推導依據 |
| `aliases` | 由 `index_alias` 推導 | 各 index 的 alias，見下方 |
| `index_name` | 同 `index_alias` | 只在建立／匯入 text index 時當預設值；平常不必設，由 rake 引數指定 |
| `request_timeout` | 120 | 秒 |

### alias 的推導

`index_alias` 裡的 `text` 會被換成其他 index 種類：

| `index_alias` | text | notes | titles |
|---|---|---|---|
| `cbeta_text_current`（production） | `cbeta_text_current` | `cbeta_notes_current` | `cbeta_titles_current` |
| `cbeta_text_staging`（staging） | `cbeta_text_staging` | `cbeta_notes_staging` | `cbeta_titles_staging` |

因此**既有的 cb.yml 不必修改**就能涵蓋三個 index。要各自指定時再寫：

```yaml
production:
  elasticsearch:
    url: 'http://localhost:9200'
    index_alias: 'cbeta_text_current'
    aliases:
      notes: 'cbeta_notes_current'
      titles: 'cbeta_titles_current'
```

沒有設 `elasticsearch:` 區塊時會退回環境變數
（`ELASTICSEARCH_URL`／`CBETA_ES_INDEX_ALIAS`／`CBETA_ES_INDEX_NAME`），再退回上表的預設值。

## 4. 首次建立 index

index 名稱要帶季號與序號，**不可以用 alias 名稱**（會被拒絕）。staging 與 production
各自一份 index，完全隔離。

```sh
cd /var/www/cbeta-api-staging/current

# 三份 XML 由既有的 manticore:x2t / t2x / notes / titles 產生
ls -lh data/manticore-xml/{text,notes,titles}.xml

# 一次建好三個 index、匯入、切 alias
RAILS_ENV=staging be rake 'elastic:rebuild_all[2026r3]'

# 確認
RAILS_ENV=staging be rake elastic:info
RAILS_ENV=staging be rake 'elastic:analyze[阿含]'
```

單獨處理某一個 index 時第一個引數是種類（`text` / `notes` / `titles`）：

```sh
RAILS_ENV=staging be rake 'elastic:rebuild[notes,cbeta_notes_2026r3_001]'
```

各 index 的規模（2026R3 實測）：

| index | 筆數 | ES index 大小 | 匯入耗時 |
|---|---|---|---|
| text | 22,037 卷 | 1.4 GB | 約 2.5 分鐘 |
| notes | 2,182,414 條 | 約 0.4 GB | 約 12 分鐘 |
| titles | 4,904 部 | 0.6 MB | 約 1 秒 |

## 4-1. 從既有環境升級到 5.1.0

伺服器實況（2026-09-10 實測）：

```
$ curl -s 'http://localhost:9200/_cat/aliases?h=alias,index'
cbeta_text_staging  cbeta_text_2026r3_001
```

也就是：**staging 已在 5.0.x（text 走 ES），production 還是 Manticore 舊版**
（`/stable` 的搜尋結果仍帶 `SQL` 欄位，且沒有 `cbeta_text_current` alias）。
兩邊的升級步驟因此不同。

### index 命名的改變

5.1.0 起 index 名稱由 alias 推導（見 `IndexBase.versioned_index_name`），
避免 staging 與 production 在同一個 Elasticsearch 上撞名：

| 角色 | alias | index 名稱 |
|---|---|---|
| production | `cbeta_text_current` | `cbeta_text_2026r3_001` |
| staging | `cbeta_text_staging` | `cbeta_text_staging_2026r3_001` |

舊的 `cbeta_text_2026r3_001` 是 staging 用**舊命名**建的。它佔用的正是
production 將來輪到 2026R3 時要用的名字，所以這次升級順便換掉。

### staging（5.0.x → 5.1.0）

```sh
cd /var/www/cbeta-api-staging/current

# 三個 index 一起重建成新命名（text 約 3 分、notes 約 6 分、titles 數秒）
RAILS_ENV=staging be rake 'elastic:rebuild_all[2026r3]'

# 異體字表要在 text index 建好之後才能匯入
RAILS_ENV=staging be rake import:vars

RAILS_ENV=staging be rake elastic:info      # 確認三個 alias 都指到新 index
```

確認無誤後刪掉舊命名的 index：

```sh
curl -X DELETE 'http://localhost:9200/cbeta_text_2026r3_001'
```

### production（Manticore → Elasticsearch，首次）

production 目前完全沒有 ES index，所以是**先部署程式、再建 index**，
中間 `/search`、`/search/notes`、`/search/title`、`/search/variants`
會回 502「全文檢索索引尚未建立」。

**請先與主管確認這個停機視窗。** 依本機實測，三個 index 合計約 10~15 分鐘。

1. 在 `shared/config/cb.yml` 的 `production:` 區塊加上 `elasticsearch:`（見 §3）。
2. `cap production deploy`
3. 立刻建 index（季號用 production 當時的資料季別，例如 2026R2）：

   ```sh
   cd /var/www/cbeta-api-production/current
   RAILS_ENV=production be rake 'elastic:rebuild_all[2026r2]'
   RAILS_ENV=production be rake import:vars
   ```
4. 清 Rails cache：cache key 沒變，但內容來自不同後端。
5. `RAILS_ENV=production be rake elastic:info` 確認三個 alias 都有指向。

要縮短停機視窗的話，可以在 `cap production deploy` 之前先進到新的 release 目錄
把 index 建好（rake 只讀 `shared/data/manticore-xml/*.xml`，不影響仍在服務的舊版），
切換 release 之後只剩 `import:vars` 與清 cache。

## 5. 驗證

```sh
# 與線上 API 的結果對照（golden values 在 test/fixtures/files/search_golden.json，
# 該檔的 _meta 記著是從哪個來源、什麼時候抓的）
RAILS_ENV=staging be rake 'elastic:verify_golden[https://cbdata.dila.edu.tw/dev]'
```

### 環境對照（2026-09-10 更新）

| 對外路徑 | deploy 目錄 | slot | 季號 | 資料日期 |
|---|---|---|---|---|
| `/stable` | `cbeta-api-production` | cbapi2 | 2026R2（`v=2`） | 2026-08 |
| `/dev` | `cbeta-api-staging` | cbapi3 | 2026R3（`v=3`） | 2026-09-09 |

**staging 是下一季的準備環境，不是 production 的複本。**
2026R3 的 `rake quarterly` 已於 2026-09-09 在 server 上跑完，`/dev` 的 Manticore
`text3`／`notes3`／`titles3`／`chunks3` 都已建好，因此：

* **第二期的 golden 從 `/dev` 抓**（那裡的 Manticore 結果與 staging 的 XML 同季，
  可以做逐筆精確比對，不必再用「差異落在資料版本」來解讀）。
* staging 上建 ES index 時，**用 staging 自己的 XML**，才會與 staging 的
  `data/kwic`（同季）一致；若改用 production 的 text.xml，多出來的卷在 staging 的
  KWIC 資料裡不存在，`all_in_one` 會回 500。
* `similar` 仍走 Manticore chunks index，不在 ES 的驗證範圍。

差異若都是同方向的小幅偏差，通常是資料版本不同；判讀方式見
[elasticsearch-migration.md](elasticsearch-migration.md) 的「驗證結果」。

需要重新抓基準時（例如換季）：

```sh
be rake 'elastic:fetch_golden[https://cbdata.dila.edu.tw/stable]'
```

## 6. 每季流程

`text.xml` 產出後（既有的 `manticore:x2t`）：

```sh
# 一次做完三個 index：建 index → 匯入 → 切 alias
RAILS_ENV=production be rake 'elastic:rebuild_all[2026r2]'
```

想先驗證再切換的話分兩步（以 notes 為例）：

```sh
RAILS_ENV=production be rake 'elastic:create_index[notes,cbeta_notes_2026r2_001]'
RAILS_ENV=production be rake 'elastic:import[notes,cbeta_notes_2026r2_001]'
# 驗證後才切 alias（原子操作，隨時可切回舊 index）
RAILS_ENV=production be rake 'elastic:promote[notes,cbeta_notes_2026r2_001]'
```

異體字表（`rake import:vars`）要過濾「CBETA 沒用到的字」，靠 Elasticsearch 的
text index 判斷，因此**必須排在 `elastic:rebuild_all` 之後**。季度流程已經照這個
順序排（見 `lib/tasks/quarterly/section-elastic.rb`）。

`create_index` 與 `rebuild` 會**擋下**「重建 alias 目前指向的 index」，避免線上搜尋中斷。

確認沒問題、也不需要回滾之後，再刪掉舊 index：

```sh
RAILS_ENV=production be rake elastic:info      # 先確認各 alias 指向哪一個
curl -X DELETE 'http://localhost:9200/cbeta_text_2026r1_001'
curl -X DELETE 'http://localhost:9200/cbeta_notes_2026r1_001'
curl -X DELETE 'http://localhost:9200/cbeta_titles_2026r1_001'
```

## 常用指令

```sh
docker compose -f /home/ray/cbeta-es/compose.yaml ps
docker compose -f /home/ray/cbeta-es/compose.yaml restart
docker logs --tail 50 cbeta-es

RAILS_ENV=staging be rake elastic:info                  # 連線、index、alias 現況
RAILS_ENV=staging be rake 'elastic:analyze[法鼓]'        # 看 analyzer 怎麼切詞
curl -s 'http://localhost:9200/_cat/indices?v'
```

## 疑難排解

| 症狀 | 檢查 |
|---|---|
| 容器起不來 | `docker logs cbeta-es`；多半是 `/var/lib/cbeta-es` 權限不是 `1000:0` |
| docker 指令回 permission denied | 該帳號不在 `docker` group（`ray` 已在其中，不必用 sudo） |
| 啟動時 memory lock 警告 | compose 的 `ulimits.memlock` 要是 `-1`；host 的 `vm.max_map_count` 需 ≥ 262144 |
| 匯入中途 timeout | 調高 `cb.yml` 的 `request_timeout` |
| 搜尋回 502 | Rails 連不到 ES。確認容器在跑、`cb.yml` 的 `url` 正確 |
| `elastic:rebuild` 被 abort | 該 index 正是 alias 指向的；改用新的序號，完成後再 `promote` |
| `rake import:vars` 匯入 0 筆 | text index 還沒建好或 alias 沒切；先跑 `elastic:rebuild_all` |
| staging 動作影響到 production | 兩邊的 `cb.yml` 用了同一個 `index_alias`，必須分開 |
