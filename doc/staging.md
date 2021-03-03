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
  * create database cbdata15;
  * grant all privileges on database cbdata15 to pg_cbdata;
  * ALTER DATABASE cbdata15 OWNER TO pg_cbdata;
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
    be rake db:schema:load DISABLE_DATABASE_ENVIRONMENT_CHECK=1

再把 analytics 加回 database.yml

## Runbook

server 端 編輯 ~/.bashrc
    alias be='bundle exec'

執行批次處理
    screen
    be rake quarterly:run[staging]
