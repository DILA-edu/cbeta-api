# Install Sphinx for Mac

以下命令會自動安裝 mysql

    brew install sphinx

## sphinx configuration for Mac

    /Users/ray/Documents/Projects/CBETAOnline/sphinx/sphinx.conf

## Build Index

詳見: sphinx-build-index.md

## Application Config

設定使用哪一個 index, 編輯 config/environments/development.rb

    config.sphinx_index = 'cbeta'

## Start Search Engine

    cd /Users/ray/Documents/Projects/CBETAOnline/sphinx
    brew services start mysql
    searchd

如果沒有啟動 search engine, 會出現如下錯誤訊息：

    Can't connect to MySQL server

## MySQL Command Line

    mysql -h0 -P9306

如果出現 `command not found: mysql`
那要編輯 ~/.zshrc

    export PATH="/usr/local/opt/mysql@5.7/bin:$PATH"
