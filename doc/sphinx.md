# Sphinx Search

環境: Ubuntu 20.04.1 LTS

## Install

$ sudo apt-get update
$ sudo apt-get install sphinxsearch
$ searchd

可以看到版本是 Sphinx 2.2.11

## sphinx configuration

如果欄位有變更，要修改 /etc/sphinxsearc 裡的下列檔案：

* sphinx.conf
* cbdata1.conf
* titles1.conf
* footnotes1.conf

建立 index 存放資料夾
    cd /var/lib/sphinxsearch
    mkdir data1
    mkdir data1-titles
    mkdir data1-footnotes

## Build Index

詳見: sphinx-build-index.md

## Application Config

設定使用哪一個 index, 編輯 config/environments/production.rb

    config.sphinx_index = "cbeta#{config.x.v}"
    config.x.sphinx_footnotes = "footnotes#{config.x.v}"
    config.x.sphinx_titles = "titles#{config.x.v}"

## MySQL Command Line

    mysql -h0 -P9306

## 清除舊版 Index

/var/lib/sphinxsearch

注意 /var/lib/sphinxsearch/data 不能刪。
