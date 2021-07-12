# 每季更新

git branch: dev

CBETA XML 新一季定案後執行。

## 編輯 config 參數

* config/application.rb
* config/deploy/staging.rb
* lib/tasks/quarterly/config.rb

## 從 GitHub 更新資料

在開發端執行 `bundle exec rake quarterly:run` 最前面的 update from github

## 異體字

參考 variants.md 更新 cbeta-metadata 裡的異體字資料

## 新增典籍

執行以下命令檢查：
    rake check:metadata

如果有新增的典籍，參考 new-canon.md

### UUID

視需要產生 UUID, 參考 uuid.md

## 作譯者

由 authority.dila 取得 大正藏 作譯者

    cd /Users/ray/git-repos/cbeta-metadata/creators/bin
    ruby get-creators-from-authority.rb

## Server 端執行 rake quarterly

編輯 lib/tasks/quarterly/config.rb

    bundle exec rake quarterly:view # 查看 steps
    bundle exec rake quarterly:run

執行 rake quarterly 會自動執行以下工作。

* 更新、取得 Github Repositories, 參考 update-github.md
* Prepare Data Files, 參考 prepare-files.md
* 資料初始化, 根據 doc/setup.md 做設定
* kwic 25

## heaven 比對 HTML

## change log

## EPUB 給 heaven 轉 PDF, MOBI

## 電子書

rake download:ebooks

## 檢測

/Users/ray/Documents/Projects/CBETAOnline/test

    ruby test.rb dev
    ruby test-by-change-log.rb 2019Q4
