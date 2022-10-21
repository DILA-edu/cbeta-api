# 如果有 新增藏經 ID 或 新加入的佛典

## 更新 cbeta metadata

以下相對目錄位於 <https://github.com/DILA-edu/cbeta-metadata>

### category

2022 Q4 起改用 Authority.

手動編輯 category/work_categories.json

### catalog

* 參考 CBReader 使用的部類目錄: <https://github.com/heavenchou/cbwork-bin/tree/master/cbreader2X>
  * bulei_nav.xhtml
* 更新部類目錄：手動編輯 catalog/cbeta.xml
* 更新冊別目錄：例如呂澂著作，編輯 catalog/vol-lc.xml

### textref

執行 textref/convert.rb

* input
  * titles/titles-by-canon
  * creators/creators-by-canon
  * time/year-by-canon
* output: textref/cbeta.csv

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
