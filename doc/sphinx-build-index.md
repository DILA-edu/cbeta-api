# Build Sphinx Index

## 將 cbeta xml p5a 轉為純文字

先把 XML P5a 轉為 text, 轉全部：

    rake sphinx:x2t

只轉某部藏經：

    rake sphinx:x2t[A]

## 將 txt 轉為 sphinx 格式的 xml

需要部類、時間資訊，要執行過：

    rake import:category
    rake import:time

然後執行：

    rake sphinx:t2x

## 將 cbeta xml p5a 校注、夾注 轉為 xml for sphinx

    rake sphinx:notes

目前校註筆數： 1,056,107

## xml for sphinx search titles

    rake sphinx:titles

## 重建索引

### development

    cd /Users/ray/Documents/Projects/CBETAOnline/sphinx

視需要修改 sphinx.conf

    indexer --rotate cbeta
    indexer --rotate notes
    indexer --rotate titles

### production

建資料夾

    sudo mkdir /var/lib/sphinxsearch/data4
    sudo chown -R sphinxsearch:root data4

視需要更新 設定檔

    /etc/sphinxsearch/sphinx.conf
    /etc/sphinxsearch/cbdata4.conf
    /etc/sphinxsearch/footnotes4.conf
    /etc/sphinxsearch/titles4.conf

建索引

    sudo indexer cbeta4
    sudo indexer footnotes4
    sudo indexer titles4

如果建索引後要更新：

    cd /etc/sphinx
    sudo indexer --rotate cbeta4
    sudo indexer --rotate footnotes4
    sudo indexer --config /etc/sphinx/sphinx.conf --rotate notes1
    sudo indexer --rotate titles4

重新啟動 service

    sudo searchd --stop
    sudo chown -R sphinx:sphinx /var/lib/sphinx
    sudo service sphinx restart

### CbetaOnline.cn

#### Config

/etc/sphinxsearch/
sphinx.conf
cbdata7.conf

#### Index

建資料夾
    $ mkdir /mnt/CBETAOnline/sphinxsearch
    $ mkdir /mnt/CBETAOnline/sphinxsearch/data7

編輯 /etc/default/sphinxsearch
    # Should sphinxsearch run automatically on startup? (default: no)
    # Before doing this you might want to modify /etc/sphinxsearch/sphinx.conf
    # so that it works for you.
    START=yes

建 index

    sudo indexer --rotate cbeta7

    sudo chown -R ray:sphinxsearch /mnt/CBETAOnline/sphinxsearch
    sudo service sphinxsearch start
