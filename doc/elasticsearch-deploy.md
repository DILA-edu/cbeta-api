# Elasticsearch 部署（sakya）

搜尋後端的 text index 由 Manticore 改為 Elasticsearch，背景與決策見
[elasticsearch-migration.md](elasticsearch-migration.md)。

**staging 與 production 是同一台機器**（`sakya.dila.edu.tw`，只有 `deploy_to` 目錄不同），
因此共用同一個 Elasticsearch 服務，靠不同的 **index alias** 隔離。

## 伺服器現況（2026-09-08 實測）

| 項目 | 現況 | Elasticsearch 需要 |
|---|---|---|
| CPU | 10 核 | 匯入時約 2.5 分鐘（排在季度批次流程） |
| 記憶體 | 94GB，實際使用 5.7GB（Manticore 佔 7.45GB） | heap 4GB |
| 磁碟 | 1TB，使用 44%（剩 544GB） | index 約 1.4GB / 22,037 卷 |
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
      # 22,037 卷的 index 約 1.4GB，4g heap 相當充裕
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
| `index_alias` | `cbeta_text_current` | 查詢一律走這個 alias |
| `index_name` | 同 `index_alias` | 只在建立／匯入 index 時當預設值；平常不必設，由 rake 引數指定 |
| `request_timeout` | 120 | 秒 |

沒有設 `elasticsearch:` 區塊時會退回環境變數
（`ELASTICSEARCH_URL`／`CBETA_ES_INDEX_ALIAS`／`CBETA_ES_INDEX_NAME`），再退回上表的預設值。

## 4. 首次建立 index

index 名稱要帶季號與序號，**不可以用 alias 名稱**（會被拒絕）。staging 與 production
各自一份 index，完全隔離。

```sh
cd /var/www/cbeta-api-staging/current

# text.xml 由既有的 manticore:x2t 產生，位置在 shared/data/manticore-xml/text.xml
ls -lh data/manticore-xml/text.xml

# 建 index、匯入、切 alias（22,037 卷約 2.5 分鐘）
RAILS_ENV=staging be rake 'elastic:rebuild[cbeta_text_2026r1_stg_001]'

# 確認
RAILS_ENV=staging be rake elastic:info
RAILS_ENV=staging be rake 'elastic:analyze[阿含]'
```

production 同樣做法，index 名稱不帶 `stg`：

```sh
cd /var/www/cbeta-api-production/current
RAILS_ENV=production be rake 'elastic:rebuild[cbeta_text_2026r1_001]'
```

## 5. 驗證

```sh
# 與線上 API 的結果對照（golden values 在 test/fixtures/files/search_golden_<季號>.json）
RAILS_ENV=staging be rake 'elastic:verify_golden[https://cbdata.dila.edu.tw/dev]'
```

差異若都是同方向的小幅偏差，通常是資料版本不同；判讀方式見
[elasticsearch-migration.md](elasticsearch-migration.md) 的「驗證結果」。

需要重新抓基準時（例如換季）：

```sh
be rake 'elastic:fetch_golden[https://cbdata.dila.edu.tw/stable]'
```

## 6. 每季流程

`text.xml` 產出後（既有的 `manticore:x2t`）：

```sh
# 一次做完：建 index → 匯入 → 切 alias
RAILS_ENV=production be rake 'elastic:rebuild[cbeta_text_2026r2_001]'
```

想先驗證再切換的話分兩步：

```sh
RAILS_ENV=production be rake 'elastic:create_index[cbeta_text_2026r2_001]'
RAILS_ENV=production be rake 'elastic:import_text[cbeta_text_2026r2_001]'
# 驗證後才切 alias（原子操作，隨時可切回舊 index）
RAILS_ENV=production be rake 'elastic:promote[cbeta_text_2026r2_001]'
```

`create_index` 與 `rebuild` 會**擋下**「重建 alias 目前指向的 index」，避免線上搜尋中斷。

確認沒問題、也不需要回滾之後，再刪掉舊 index：

```sh
RAILS_ENV=production be rake elastic:info      # 先確認 alias 指向哪一個
curl -X DELETE 'http://localhost:9200/cbeta_text_2026r1_001'
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
| staging 動作影響到 production | 兩邊的 `cb.yml` 用了同一個 `index_alias`，必須分開 |
