# Import to RDB

## 匯入 藏經 ID

    rake import:canons

## 作品內目次 匯入 TocNode 供搜尋

如果有新增的藏經 ID，要修改 cbeta gem 裡面的 SORT_ORDER 以及 CANON 常數。
然後執行

    rake import:toc

執行某部藏經（例如：大正藏）

    rake import:toc[T]

## 匯入 全部典籍編號

如果有典籍編號有更動（例如新增藏經 ID），要更新 cbeta-metadata/work-id。

由 GitHub 上的 cbeta-metadata 匯入：

    rake import:work_id

DocuSky 會讀 cbeta-metadata/textref 裡的目錄資料，
測試版時還不要更新，等正式版再更新。

## 替代典籍 對照表 匯入資料庫

由 GitHub 上的 cbeta-metadata 匯入，
這要在上一個步驟 work id 都已匯入資料庫之後才能做：

    rake import:alt

## 匯入 部類目錄

### 比對 CBReader 的目錄是否有更新

* <https://github.com/cbeta-git/CBReader2X/blob/master/Bookcase/CBETA>
  * advance_nav.xhtml
  * bulei_nav.xhtml
  * simple_nav.xhtml

### cbeta-metadata

由 GitHub 上的 cbeta-metadata 匯入，
要在上一步 import:alt 之後執行

## 匯入 行資訊

由 XML P5a 匯入行號、該行 HTML、該行註解

    rake import:lines

花費時間約 22 分鐘。

用到此資訊的功能：根據 行首資訊 取得該行文字

### catalog

需要讀某一行所在卷數，要在 import:lines 之後做

    rake import:catalog

## 更新「典籍所屬部類」資訊

由 GitHub 上的 cbeta-metadata 匯入:

    rake import:category

## 匯入 佛典資訊

經名、卷數、title

    rake import:work_info

## 匯入「典籍跨冊」資訊

如果有新增的典籍跨冊，要更新 cbeta-metadata/special-works

這要在 import:work_info 之後做，跨冊的 title 才會對（ex: Y0030)。

由 GitHub 上的 cbeta-metadata 及 p5a 匯入:

    rake import:cross

## 匯入 作譯者

執行之前要從 authority.dila 更新【大正藏】作譯者資料到 GitHub cbeta-metadata. (參考 2019-08-29 會議記錄)

比對 authority 與 github cbeta-metadata 的【大正藏】作譯者資料差異：
（以後大正藏作譯者都以 authority 為準，這工作不必再做了）
    rake custom:compare_creators

更新 Github cbeta-metadata 之後匯入作譯者：

    rake import:creators

## 匯入地理資訊

將 Local 的 data/places.json 上傳到 shared/data/
然後執行

    rake import:place

data/places.json 來自 /Users/ray/Documents/Projects/CBETA/place

## 匯入時間資訊

由 GitHub 上的 cbeta-metadata 匯入:

    rake import:time

會產生一個全部朝代列表：log/dynasty-all.txt

## 匯入 卍續藏 行號對照表

    rake import:lb_maps

## 匯入 各卷起始行

參考 juan-line.md

## 異體字

資料來源是 https://github.com/DILA-edu/cbeta-metadata/blob/master/variants/variants.txt

    rake import:vars

## 同義詞

### 資料來源

由 data-static/synonym.txt 匯入
synonym.txt 來自 CBETA heaven 提供的 fdb_equivalent.txt 
再經轉檔程式 GoogleDrive/小組雲端硬碟/CBETA專案/階段性任務/2019-05-同義搜尋/同義詞/bin/z2u.rb
將其中的組字式轉為 unicode

### 匯入

rake import:synonym

## 更新經號排序

如果 搜尋結果的排序規則 有變動的話，要更新 cbeta gem.

然後執行

    rake update:sort_order

這會 根據 cbeta gem 裡的搜尋排序規則 更新 works, `toc_nodes` table 的 sort_order 欄位.
