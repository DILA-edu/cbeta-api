# 年度輪替 checklist

每年 CBETA 資料更新（R1 → R2 → R3 …）時，會把 app slot 輪替一輪。
本文件記錄輪替要做的事，以及為什麼版控裡的檔案一行都不用改。

## 概念：角色 symlink 與 slot 解耦

伺服器 `sakya.dila.edu.tw` 上有三個實體 slot：

    /var/www/cbapi1
    /var/www/cbapi2
    /var/www/cbapi3

以及兩條「角色」symlink：

    /var/www/cbeta-api-production -> /var/www/cbapi?
    /var/www/cbeta-api-staging    -> /var/www/cbapi?

版控裡的 `config/deploy/production.rb`、`config/deploy/staging.rb` 與伺服器上
Apache 的 `Define stable_path` / `dev_path` **都只寫角色路徑**，不寫 slot 編號。
輪替時只改 symlink，兩邊自然同步，不會出現版控與 Apache 設定不一致的情形。

查詢目前的對應關係：

    cap production slot:which
    cap staging slot:which

（等同於在伺服器上 `readlink -f /var/www/cbeta-api-production`。）

## 掛載對應

| 掛載路徑 | 角色 symlink | PassengerAppEnv | PassengerAppGroupName |
|---|---|---|---|
| `/stable` | `/var/www/cbeta-api-production` | production | `cbdata_stable` |
| `/dev` | `/var/www/cbeta-api-staging` | staging | `cbdata_dev` |

Apache 設定在 `/etc/apache2/sites-available/cbdata-sub.conf`（由 `cbdata.conf`
與 `cbdata-le-ssl.conf` 以 `Include` 引入）：

```apache
Define stable_path /var/www/cbeta-api-production
Define dev_path    /var/www/cbeta-api-staging
```

`PassengerAppGroupName` 跟著**角色**而非 slot，維持不變。

## 輪替步驟

以「cbapi2 由 staging 升為 production、cbapi3 接手 staging」為例：

1. 確認 staging（cbapi2）測試通過。
2. `dev` branch merge 進 `main`。
3. 準備新的 staging slot（cbapi3）：
   - `mkdir -p /var/www/cbapi3/shared/config`
   - 放 `database.yml`、`cb.yml`、`master.key`（見 doc/staging.md）
   - ⚠️ `cb.yml` 必須含 `api_origin_allowlist`（Origin 白名單不進版控）。
     漏了在過渡期內不會有症狀，但過渡期一結束前端就全站 401。
     部署後跑 `cap staging rake api_key:config`（或在機器上
     `RAILS_ENV=staging bundle exec rake api_key:config`）確認。
   - `database.yml` 的 `staging:` 區塊：內容 DB 指新的（如 `cbdata3`）、
     analytics 指 `analytics_dev`、**accounts 指 `accounts_dev`**
   - `database.yml` 的 `production:` 區塊：analytics 指 `cb_analytics`、
     **accounts 指 `cb_accounts`**
4. 切換角色 symlink：

   ```bash
   ln -sfn /var/www/cbapi2 /var/www/cbeta-api-production
   ln -sfn /var/www/cbapi3 /var/www/cbeta-api-staging
   ```

5. `sudo systemctl reload apache2`
6. Passenger 會 resolve realpath，改完 symlink 必須 restart：

   ```bash
   cap production deploy:restart
   cap staging deploy:restart
   ```

7. 用 `cap production slot:which` / `cap staging slot:which` 驗證。

## accounts DB 不隨輪替搬移

內容 DB（primary）每年隨資料更新清掉重建，但**使用者與 API key 資料放在獨立的
accounts DB**，固定為：

| 環境 | accounts DB |
|---|---|
| production | `cb_accounts` |
| staging | `accounts_dev` |

做法是每個 slot 的 `shared/config/database.yml` 中，`production:` 區塊的 accounts
一律指 `cb_accounts`、`staging:` 區塊一律指 `accounts_dev`。切換 `PassengerAppEnv`
時就自動換過去，**輪替 checklist 不必多一步搬資料**。

附帶效果：staging 測試期間產生的帳號留在 `accounts_dev`，不會汙染 production。

## 注意事項

- Capistrano 的 `deploy_to` 指向 symlink 完全正常，`releases/` 與 `shared/`
  都建在實體目錄內。
- `cbdata-cn.conf`（`api.cbetaonline.cn`，`PassengerAppEnv cn`）目前直接寫
  slot 路徑 `/var/www/cbapi1/current/public`，輪替時**要另外確認這一份**。
  見 doc/cn.md。
- 代價：「現在誰是 production」在版控裡看不到，只能問伺服器
  （`cap production slot:which`）。這是刻意的取捨 —— 換來的是輪替時不必改版控。
