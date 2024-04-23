# 每季更新

git branch: dev

CBETA XML 新一季定案後執行。

## 編輯 config 參數

* config
  * cb.yml
  * deploy
    * staging.rb
    * production.rb
* app/views/static_pages
  * home.haml 製作日期
  * log.haml

## 從 GitHub 更新資料

在開發端執行 `bundle exec rake quarterly` 
只做最前面的 update from github

## Update cbeta-metadata on GitHub

### 異體字

參考 variants.md 更新 cbeta-metadata 裡的異體字資料

### 新增佛典

執行以下命令檢查：
    rake check:metadata

如果有新增的佛典，參考 new-canon.md

## update cbeta gem

* 缺字資料要更新

## UUID

視需要產生 UUID, 參考 uuid.md

## Server 端執行 rake quarterly

使用 direnv 管理 環境變數, 編輯 /var/www/cbapi?/.envrc
    export RAILS_ENV=staging

編輯 config/cb.yml

執行 rake quarterly 會自動執行以下工作。

* 更新、取得 Github Repositories, 參考 update-github.md
* Prepare Data Files, 參考 prepare-files.md
* 資料初始化, 根據 doc/setup.md 做設定
* kwic 25

## heaven 比對 HTML

## change log

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
  * cbdata-cn.conf (cbetaonline.cn 會呼叫 api.cbetaonline.cn)

檢視 config/database.yml
production analytics database 應為 cb_analytics

使用 direnv 管理 環境變數, 編輯 /var/www/cbapi?/.envrc
    export RAILS_ENV=production

## 建立下一季開發環境

* 建 database, 參考 postgresql.md
* 參考 staging.md
