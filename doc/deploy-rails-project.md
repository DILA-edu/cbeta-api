# Deploy Rails Project

## deploy 目標路徑

`config/deploy/production.rb` 與 `config/deploy/staging.rb` 的 `deploy_to`
指向「角色 symlink」而非 slot 編號：

    /var/www/cbeta-api-production -> /var/www/cbapi?
    /var/www/cbeta-api-staging    -> /var/www/cbapi?

年度輪替時只改這兩條 symlink，版控裡不用動。目前的對應關係用
`cap production slot:which` 查詢。詳見 [doc/annual-rotation.md](annual-rotation.md)。

在 server 上建立 project folder（新的 slot）

    mkdir /var/www/cbapi3
    chown ray:www-data /var/www/cbapi3

在 local 端 project root 下執行

* 測試版: cap staging deploy
* 正式版: cap production deploy

## 設定 secrets.yml

把 local 端的 config/secrets.yml 傳到 server 端 shared/config/secrets.yml

在 local 端執行 rake secret 得到一個新的 secret key

把這個新的 secret key 寫到 shared/config/secrets.yml

    production:
      secret_key_base: xxxxxxxxxx

## 設定 database.yml

rails 根據 database.yml 來連上資料庫。下一步在 server 上的 project root 建立 shared/config/database.yml

    production:
      adapter: postgresql
      encoding: unicode
      database: cbdata13
      host: localhost
      pool: 5
      username: pg_cbdata
      password: 1234

上面的密碼 1234 要換成真正的密碼

在 local 端再次執行

    cap production deploy

## 設定 nginx

參考 nginx.md

## 清除舊 migration

migration 資料夾裡的舊 migration 可以移除。

執行 `rake db:schema:load` 會根據 db/schema.rb 建立資料庫。

執行 `rake -T db` 可以查看有哪些 db tasks.
