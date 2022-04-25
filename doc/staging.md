# 建立 server 測試環境

## Config

* 修改 config/deploy.rb
  * set application
* 修改 config/deploy/staging.rb
  * deploy_to

## Deploy

cap staging deploy

## PostgreSQL

* 進入 psql
  * sudo su - postgres
  * psql
* 建資料庫
  * create database cbdata3;
  * grant all privileges on database cbdata3 to pgcbapi;
  * ALTER DATABASE cbdata3 OWNER TO pgcbapi;
* 離開 psql
  * \q
  * exit
* 測試連線
  * sudo su - pg_cbdata
  * psql -d cbdata15 -U pg_cbdata
  * \q
  * exit

database.yml 裡先只放 primary, 先不放存取記錄 (analytics), 以免被清掉.

新建 tables
    RAILS_ENV=staging be rake db:schema:load

tables 建好後，再把 analytics 加回 database.yml。

## 更新異體字資料

1. Update CBETA 缺字資料庫 from GitHub
2. 執行 <https://gitlab.com/dilada/variants> 裡的 /dila/bin/cbdata.rb
   產生 vars-for-cbdata.json，
   這會合併 Unicode、教育部異體字典、CText、CBETA 等資料。
3. 將 vars-for-cbdata.json 公開至 <https://github.com/DILA-edu/cbeta-metadata> 裡的 variants

## Runbook

server 端 編輯 ~/.bashrc
    alias be='bundle exec'

執行批次處理
    screen
    be rake quarterly:run[staging]
