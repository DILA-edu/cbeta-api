# 初始設定

## 從 Github 更新相關資料

* cbeta_gaiji
* cbeta-xml-p5a
* cbeta-metadata

## 檢查 CBETA XML P5a

    rake check:p5a

## 缺字資料

檢查 xml p5a 的缺字是否都有對應的缺字資訊了：

    rake check:gaiji

### 缺字資訊 匯入 RDB

供搜尋組字式使用

    rake import:gaiji

## 各卷內文 HTML 檔

### x2h

讀取 CBETA XML P5a, 每個校勘版本、每一卷都產生一個 HTML 檔
先暫存在 data/html-editions-tmp, 再移到 data/html-editions

執行全部大約 65 分鐘.

(假設發行日期為 2020-01)

    rake convert:x2h[2020-08]

執行某部藏經（例如：大正藏，只做大正藏大約 30 分鐘）

    rake 'convert:x2h[2020-08,T]'

### 給 heaven 比對

打包給 heaven 比對 (做過 Projects/CBETAOnline/test 之後)

    cd /var/www/cbdata10/shared/data
    zip -r html.zip html

因為 heaven 可能發現問題再修改 XML,  
所以等 heaven 比對完再進行後面的步驟。

## 作品內目次 轉為 一部作品一個 JSON 檔

執行

    rake convert:toc

讀取 CBETA XML P5a, 產生作品內目次，一部作品一個 JSON 檔
放在 data/toc 裡面

執行某部藏經（例如：大正藏）

    rake convert:toc[T]

## 相關資料匯入 RDB

參考 rdb.md

## 產生供下載用的各種檔案

參考 convert-for-download.md

## Create Sphinx Index

參考 sphinx.md

## Create KWIC Index

參考 kwic.md
