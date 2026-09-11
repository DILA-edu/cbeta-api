# Apache2 設定

## CORS

要讓其他開發者在不同 domain 也能使用 API.

$ sudo a2enmod headers

$ sudo editor /etc/apache2/sites-available/cbdata-le-ssl.conf

    <VirtualHost *:443>
      ...
      Header set Access-Control-Allow-Origin "*"
      ..
    </VirtualHost>

測試語法
$ sudo apachectl -t

$ sudo service apache2 restart

## 清掉 client 送來的 X-Forwarded-For

本站是 Apache + Passenger 直接對外，前面**沒有**反向 proxy，所以 request 裡的
`X-Forwarded-For` 必定是 client 自己捏的。

但 Rails 的 `request.remote_ip` 會優先採信這個 header。後果是：

- rate limit（`ApiKeyAuthentication`）的額度桶可以用這個 header 隨意換，
  輪替它就能無限繞過 60/min；
- Rails 內建的 `Started ... for <IP>` 也是用 `remote_ip`，而 `cbeta-api-r3`
  fail2ban jail 抓的就是那一行 —— 既能規避計數，也能讓它去 ban 無辜的第三方 IP。

在 vhost 內加一行把它清掉（`mod_headers` 在上面的 CORS 設定就已經啟用）：

    <VirtualHost *:443>
      ...
      RequestHeader unset X-Forwarded-For
      ...
    </VirtualHost>

    $ sudo apachectl -t
    $ sudo service apache2 restart

這樣 `remote_ip` 就等於 `remote_addr`（TCP 連線的對端，偽造不了）。

⚠️ 哪天真的在前面放了 CDN 或 load balancer，這一行要拿掉，並改設
`config.action_dispatch.trusted_proxies`，否則所有人會被算成同一個 IP。
相關說明見 doc/api-key-design.md 3.4、6.6。

驗證：連送 60 次帶同一個 `X-Forwarded-For` 到 429 之後，換一個
`X-Forwarded-For` 再送。設定正確的話仍然是 429（與不帶 header 時同一個桶）；
若恢復 200，表示 header 還是被採信。
