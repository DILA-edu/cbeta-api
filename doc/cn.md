# cbetaonline.cn

## 架構與回源(CDN)

`api.cbetaonline.cn` 走**阿里雲 CDN**,不是直連源站:

```
api.cbetaonline.cn → CNAME *.w.kunluncan.com（阿里雲 CDN，server: Tengine）→ 回源 → sakya
```

- **源站(origin)**:應指向 sakya(`cbdata.dila.edu.tw` 後面的主機;sakya 內網 IP 在 NAT 後,CDN 要用 DILA 對外的 public IP / 網域)。
- sakya 上對應的 vhost 是 `/etc/apache2/sites-available/cbdata-cn.conf`(`*:443`,`ServerName api.cbetaonline.cn`,`DocumentRoot /var/www/cbapi1/current/public`,`PassengerAppEnv cn`)。它與 `https://cbdata.dila.edu.tw/stable` 服務同一份 `/var/www/cbapi1/current`(差別是 cn 走 root path、stable 走 `/stable` 前綴)。
- **回源設定**:協議用 **HTTPS(443)**(cn vhost 只有 `*:443`,沒有 `:80`),且**回源 Host 設為 `api.cbetaonline.cn`**(回源 SNI 也帶這個),才會命中 `cbdata-cn.conf`。
- 阿里雲 CDN 帳號由中國端管理,CDN 層的源站 / 回源設定要找該帳號的管理者改;sakya 與本 repo 都改不了。

### 排查:前端出現 Apache「Forbidden」

1. `curl -I https://api.cbetaonline.cn/` 看回應 header:有 `server: Tengine` / `eagleid` / `x-alicdn-da-ups-status` 就是 CDN 回的;`ups-status: ...,403` 代表是**源站回 403**。
2. 比對錯誤頁的 `Apache/x.y.z` 版本與 sakya 實際版本(`apache2 -v`)。**版本對不上 → CDN 源站指到了錯誤/舊主機**,不是 sakya 的問題。
3. 直接測 sakya 上的 cn vhost(用正確 SNI),正常應回 200:

   ```
   curl -ksi --resolve api.cbetaonline.cn:443:127.0.0.1 https://api.cbetaonline.cn/
   ```

4. 在 sakya 的 access.log 找 `host=api.cbetaonline.cn`;**完全沒有紀錄 → CDN 回源根本沒打到 sakya**(源站位址設錯)。

## xml 更新特定 tag

    cd /mnt/CBETAOnline/git-repos/cbeta-xml-p5a
    git pull
    git checkout tags/2021Q1

## 半自動 runbook

  rake quarterly_cn

## 電子書

    curl -C - -O http://cbdata.dila.edu.tw/dev/download/cbeta-epub-2020q4.zip
    curl -C - -O http://cbdata.dila.edu.tw/dev/download/cbeta-mobi-2020q4.zip
    
    curl -C - -O http://cbdata.dila.edu.tw/dev/download/cbeta-pdf-2020q4-1.zip
    unzip cbeta-pdf-2020q4-1.zip

    curl -C - -O http://cbdata.dila.edu.tw/download/cbeta-pdf-2020q4-2.zip

續傳

    curl -C - -O [URL]

curl Options

-O, --remote-name   Write output to a file named as the remote file
-C, --continue-at OFFSET  Resumed transfer OFFSET

## Sphinx

    sudo indexer --rotate cbeta7

## secret_key_base

    EDITOR="code --wait" bin/rails credentials:edit --environment cn

上面命令會做以下動作：

* 建立 config/credentials/cn.key 如果沒有的話。這個檔不要送上 Git.
* 建立 config/credentials/cn.yml.enc 沒果沒有的話。這個檔要送上 Git.
* 解碼並使用編輯器 code 開啟 cn credentials 檔案。
