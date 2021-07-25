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
