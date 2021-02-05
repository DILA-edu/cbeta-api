# juan-line

先將資料準備在 data/juan-line, 如果資料有更新，可執行以下命令產生新資料：

    rake convert:juanline

或直接從舊版複製

    cp -r /var/www/cbdata6/shared/data/juan-line /var/www/cbdata7/shared/data

然後執行以下命令將資料匯入 RDB：

    rake import:juanline
