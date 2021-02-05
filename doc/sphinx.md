# sphinx configuration

如果欄位有變更，要修改：

    /etc/sphinxsearch/sphinx.conf

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
