# cbetaonline.cn

## 架構與回源(CDN)

`api.cbetaonline.cn` 走**阿里雲 CDN**,不是直連源站:

```
api.cbetaonline.cn → CNAME *.w.kunluncan.com（阿里雲 CDN，server: Tengine）→ 回源 → sakya
```

術語對照（沿用阿里雲 CDN 主控台的用詞,方便與中國端管理者溝通）:

| 文件用詞 | 英文 | 意思 |
|---|---|---|
| 源站 | origin (server) | 真正的後端伺服器(sakya) |
| 回源 | origin pull / back-to-origin | CDN 沒有快取時,往回向源站取內容的請求 |
| 回源設定 | origin config | CDN→源站那一段的設定(回源協議、回源 Host、回源 SNI、源站位址…) |

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

### 排查:前端出現「421 Misdirected Request」

錯誤頁 Server 是 sakya 自己的 `Apache/2.4.58 (Ubuntu)`(代表回源**已打到 sakya**),
內文寫 *the requested host name does not match the SNI*。成因是 **CDN 回源走 HTTPS 但
沒帶 SNI(或 SNI ≠ `api.cbetaonline.cn`)**,加上 **cn vhost 與預設 vhost 用的憑證不同**:
無 SNI 時 Apache 落到預設 vhost(`sakya.dila.edu.tw`,DILA 憑證)完成 TLS 握手,但 HTTP
`Host:` 是 `api.cbetaonline.cn`(對應 cn vhost),兩個 vhost 的 SSL 設定不相容 → Apache 2.4 回 **421**。

1. 外部 `curl -I https://api.cbetaonline.cn/` → `421`,且 `x-alicdn-da-ups-status: ...,421`(源站回源回 421)。
2. sakya 的 error.log 會持續出現(來源為阿里雲回源節點 IP,如 `163.181.223.x`):

   ```
   AH02032: Hostname sakya.dila.edu.tw (default host as no SNI was provided)
   and hostname api.cbetaonline.cn provided via HTTP
   have no compatible SSL setup for policy 'secure'
   ```

   關鍵字 **`no SNI was provided`**。
3. **先查 cn vhost 的憑證**(2026-06 這次的真正肇因:它是自簽且 2022 年就過期):

   ```
   echo | openssl s_client -connect 127.0.0.1:443 -servername api.cbetaonline.cn 2>/dev/null \
     | openssl x509 -noout -subject -issuer -dates
   ```

4. 本地重現:

   ```
   # 帶正確 SNI → 200（cn vhost 應用本身正常）
   curl -ksi --resolve api.cbetaonline.cn:443:127.0.0.1 https://api.cbetaonline.cn/
   # 不帶 SNI（模擬回源,落到預設 vhost）+ Host 標頭 → 修好前 421 / 修好後 200
   curl -ksi -H "Host: api.cbetaonline.cn" https://127.0.0.1/
   ```

   ⚠️ 注意:上面兩條都要在 **sakya 本機**跑(`127.0.0.1` 才是 sakya)。從 DILA 內網其他機器
   連 sakya:443 會經過會終結 TLS 的設備、一律回 `*.dila.edu.tw` 憑證,測不準 cn vhost。

5. **修法(sakya 側,優先 — 2026-06-28 即以此解決)**:把 cn vhost 的憑證改成與預設 vhost
   **同一張有效的 DILA 憑證**,SSL 設定一致後,即使回源不帶 SNI 也判定相容、直接依 `Host`
   服務到 cn vhost(同時換掉過期自簽憑證)。`cbdata-cn.conf` 改成:

   ```apache
   SSLCertificateFile      /etc/ssl/certs-dila/server.cer
   SSLCertificateKeyFile   /etc/ssl/certs-dila/server.key
   SSLCertificateChainFile /etc/ssl/certs-dila/uca.cer
   ```

   `sudo apache2ctl configtest && sudo systemctl reload apache2`,再用步驟 4 第二條驗證(應變 200)。
6. **正規做法(CDN 側,選配)**:請中國端在阿里雲 CDN「回源配置」設 **回源 SNI = `api.cbetaonline.cn`**
   (回源協議 HTTPS、回源 HOST 維持 `api.cbetaonline.cn`)。做了這項後即使源站多 vhost 也不依賴憑證對齊。

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
