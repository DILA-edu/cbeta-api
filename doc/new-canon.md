# 如果有 新增藏經 ID 或 新加入的典籍

## 更新 cbeta metadata

以下相對目錄位於 <https://github.com/DILA-edu/cbeta-metadata>

### category

手動編輯 category/work_categories.json

### catalog

* 參考 CBReader 使用的部類目錄: <https://github.com/heavenchou/cbwork-bin/tree/master/cbreader2X>
* 更新部類目錄：手動編輯 catalog/cbeta.xml
* 更新冊別目錄：例如呂澂著作，編輯 catalog/vol-lc.xml

### titles

執行 titles/bin/get-titles.rb

* input: CBETA XML P5a
* output:
  * titles/titles-by-canon
  * titles/all-title-byline.csv'

### creators

* 手動編輯 creators/creators-by-canon
* 執行 creators/bin/list-all.rb
  * input:
    * creators/creators-by-canon
    * titles/titles-by-canon
* 如果有新增 Authority ID, Github 上的 Authority XML 也要更新, 後面執行 `rake create:creators` 時要用到。

### time

* 手動編輯 time/year-by-canon
* 執行 time/bin/dynasty-all.rb
  * input: titles/titles-by-canon
  * output
    * time/dynasty-works.json
    * time/dynasty-all.csv'

### textref

執行 textref/convert.rb

* input
  * titles/titles-by-canon
  * creators/creators-by-canon
  * time/year-by-canon
* output: textref/cbeta.csv

如果典籍有跨冊，要更新 special-works.

### 更新 替代典籍

各部藏經重複收錄的典籍，CBETA 只收錄一次，例如 X0002 《父子合集經》在大正藏之中已經有了 T0320，CBETA 就不收錄 X0002，而是建立 X0002 與 T0320 的對應關係。

有新的藏經加入時，要更新這份對應清單。執行 /Users/ray/Documents/Projects/cbeta/catalog/bin/alt.rb 會從 CBReader 的 Toc 資料取出對應關係表。

將新的對照表更新到：<https://github.com/DILA-edu/cbeta-metadata/tree/master/alternates>

### work-id

根據 xml p5a 以及上一步驟的「替代典籍 對照表」，產生全部的 work id:

    /Users/ray/Documents/Projects/cbeta/catalog/bin/work-id.rb

來自「替代典籍 對照表」的 work id 會缺少冊數，這需要手動根據 cbeta-metadata/catalog/cbeta.xml 裡的資訊補上

更新到 cbeta metadata

    https://github.com/DILA-edu/cbeta-metadata/tree/master/work-id

## TextRef

DocuSky 會讀 cbeta-metadata/textref 裡的目錄資料，
這裡的資料也要更新，但要等正式版上線再更新，
否則 DocuSky 會與 CBETA Online 正式版不同步。

## 更新 ruby gem: cbeta

### lib/cbeta.rb

  CANON = 'DA|GA|GB|LC|ZS|ZW|[A-Z]'
  SORT_ORDER = %w(T X A K S F C D U P J L G M N ZS I ZW B GA GB Y LC)

### lib/data/canons.csv

新增該部藏經的版本略符等 metadata 資料。

## Create UUID

參考 uuid.md
