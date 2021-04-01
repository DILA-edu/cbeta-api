# 每季更新

## 正式版上線

* fix bug 直接改正式版 (git branch: master)
  * merge 到 dev branch

## 測試版 新建 測試環境 (git branch: dev)

參考 staging.md

## 測試版 建立下一季測試環境 (git branch: dev)

* CBETA XML 新一季定案
* 編輯 config 參數
  * config/application.rb
  * config/deploy/staging.rb
  * lib/tasks/quarterly/config.rb
* 開發端
  * 參考 variants.md 更新 cbeta-metadata 裡的異體字資料
  * `bundle exec rake quarterly:run` 執行最前面的 update from github
  * 參考 uuid.md 產生新的 UUID (如果有新的話)
  * 由 authority.dila 取得 大正藏 作譯者
    * cd /Users/ray/git-repos/cbeta-metadata/creators/bin
    * ruby get-creators-from-authority.rb
* server 端
  * bundle exec rake quarterly:view # 查看 steps
  * bundle exec rake quarterly:run
* heaven 比對 HTML
* 電子書
  * 下載 heaven 做好的 PDF, MOBI
    * curl -C - -O https://archive.cbeta.org/download/pdf_a4/cbeta_pdf_1_2021q1.zip
    * curl -C - -O https://archive.cbeta.org/download/pdf_a4/cbeta_pdf_2_2021q1.zip
    * curl -C - -O https://archive.cbeta.org/download/mobi/cbeta_mobi_2021q1.zip

## 開發端 複製 Rails Project

參考 new-rails-project.md

## 新增典籍

執行以下命令檢查：
    rake check:metadata

如果有新增的典籍，參考 new-canon.md

### UUID

視需要產生 UUID, 參考 uuid.md

## Updata 大正藏 作譯者 from Authority.DILA

    執行 cbeta-metadata/creators/bin/get-creators-from-authority.rb

### Server PostgreSQL 設定

參考 postgresql.md

## Deployt to server

參考 deploy-rails-project.md

## Server 端執行 rake quarterly

編輯 lib/tasks/quarterly/config.rb

執行 rake quarterly 會自動執行以下工作。

* 更新、取得 Github Repositories, 參考 update-github.md
* Prepare Data Files, 參考 prepare-files.md
* 資料初始化, 根據 doc/setup.md 做設定
* Change Log, 參考 /Users/ray/Documents/Projects/CBETA/ChangeLog/README.md
* kwic 25

### 檢測

/Users/ray/Documents/Projects/CBETAOnline/test

    ruby test.rb dev
    ruby test-by-change-log.rb 2019Q4

### 移除舊版

參考 remove-old.md

### cn mirror

等正式版上線後再更新 cn mirror, 參考 cn.md.
