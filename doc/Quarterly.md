# 每季更新

git branch: dev

CBETA XML 新一季定案後執行。

## 編輯 config 參數

* config
  * cb.yml (server 端，每個 slot 的 shared/config 各一份)
    * git, v, r, r_prev, pub, elasticsearch
    * ⚠️ api_origin_allowlist 不進版控，新 slot 容易漏掉
    * ⚠️ elasticsearch 區塊也不進版控；`index_alias` 必須與另一個角色不同
      （production `cbeta_text_current`、staging `cbeta_text_staging`），
      見 [elasticsearch-deploy.md](elasticsearch-deploy.md)
* app/views/static_pages
  * log.haml

`config/deploy/staging.rb`、`production.rb` **不用改**，deploy target 是角色
symlink，換 slot 只改伺服器上的 symlink，見 [annual-rotation.md](annual-rotation.md)。

## 從 GitHub 更新資料

在開發端執行 `bundle exec rake quarterly` 
只做最前面的 update from github

## Update cbeta-metadata on GitHub

### 異體字

參考 [variants.md](variants.md) 更新 cbeta-metadata 裡的異體字資料

### 新增佛典

執行以下命令檢查：
    rake check:metadata

如果有新增的佛典，參考 [new-works.md](new-works.md)

## gem update cbeta

https://rubygems.org/gems/cbeta

* 缺字資料要更新
  * cbeta_gaiji.json
  * cbeta_sanskrit.json

## UUID

視需要產生 UUID, 參考 [uuid.md](uuid.md)

## Server 端執行 rake quarterly

使用 direnv 管理 環境變數, 編輯 /var/www/cbapi?/.envrc
    export RAILS_ENV=staging

編輯 config/cb.yml

執行 rake quarterly 會自動執行以下工作:

* 更新、取得 Github Repositories, 參考 update-github.md
* Prepare Data Files, 參考 prepare-files.md
* 資料初始化, 根據 doc/setup.md 做設定
* 全文檢索用的 XML（`search_xml:x2t` / `t2x` / `notes` / `titles` / `chunks`），
  輸出到 `data/search-xml`。格式仍是 xmlpipe2，但 Manticore 本身已退場
* Elasticsearch 的 text / notes / titles / chunks 四個 index，
  參考 [elasticsearch-deploy.md](elasticsearch-deploy.md)
* 匯入異體字（`rake import:vars`）—— 排在 Elasticsearch 之後，
  因為過濾條件要查 ES 的 text index
* kwic

## heaven 比對 HTML

## change log

根據 CBETA 給的「忽略清單」編輯：

* `/home/ray/cbeta-change-log/`
  * 2024R3-ignore-puncs.txt
  * 2024R3-ignore-all.txt

如果檔案不存在，就表示 沒有要忽略的。

## EPUB 給 heaven 轉 PDF, MOBI

2022-07 起，EPUB 也改由 heaven 產生。

## 電子書

下載 heaven 做好的 EPUB, PDF, Mobi

    rake download:ebooks

也可以指定下載其中一種，例如：

    rake download:ebooks[epub]

## 檢測

/Users/ray/Documents/Projects/CBETAOnline/test

    ruby test.rb dev
    ruby test-by-change-log.rb 2019Q4

## 切換為正式版

修改 server 上的 /etc/apache2/sites-available
  * cbdata-sub.conf

更改項目：
  * app path, 例： 
    * `Define stable_path /var/www/cbapi1`
    * 改用角色 symlink 後這一項不必再改，見 [annual-rotation.md](annual-rotation.md)
  * ruby 版本, 例：
    * `PassengerRuby /home/ray/.asdf/installs/ruby/4.0.1/bin/ruby`

檢視 config/database.yml
* production analytics database 應為 cb_analytics
* production accounts database 應為 cb_accounts (使用者與 API key，不隨輪替搬移)

使用 direnv 管理 環境變數, 編輯 /var/www/cbapi?/.envrc
    export RAILS_ENV=production

## 清理舊季資料

三個 slot 中只有兩個有角色（production 與 staging），第三個閒置，因此「兩季之前」
的 index 一定沒有環境在用，可以回收空間。動手前先確認目前的對應：

```sh
cap production slot:which
cap staging slot:which
grep -E "^\s+v:" /var/www/cbapi?/shared/config/cb.yml   # 各 slot 的季號
```

也要確認 Apache 的 `cbdata-sub.conf` 只有 `stable_path` 與 `dev_path` 兩個掛載點，
沒有其他路徑指向要清掉的 slot。

### Manticore 殘留（一次性清理）

5.2.0 起 Rails 完全不連 Manticore（見
[elasticsearch-migration.md](elasticsearch-migration.md)）。確認四個 ES index
都正常之後，這些東西可以一次清掉，之後每季就不必再做：

```sh
# 1. 停容器
docker compose -f /home/ray/manticore3/compose.yaml down

# 2. 確認 /search、/search/notes、/search/title、/search/similar 都正常

# 3. 刪資料檔（每季一份，各約 7.4GB）與設定
sudo rm -rf /var/lib/manticore3
sudo rm -rf /etc/manticore3
```

`shared/config/cb.yml` 的 `manticore:` 區塊也可以刪掉，已經沒有程式在讀。

### Elasticsearch 舊季 index

不必改設定、也不必重啟容器，確認 alias 沒指向它就能刪：

```sh
RAILS_ENV=production bundle exec rake elastic:info    # 看各 alias 指向哪一個
curl -X DELETE 'http://localhost:9200/cbeta_text_2026r1_001'
curl -X DELETE 'http://localhost:9200/cbeta_notes_2026r1_001'
curl -X DELETE 'http://localhost:9200/cbeta_titles_2026r1_001'
```

保留前一季的 index 就能隨時 `rake 'elastic:promote[<種類>,<舊 index>]'` 退版，
確認新版穩定後再刪。

## 建立下一季開發環境

* 建 database, 參考 postgresql.md
* 參考 staging.md
