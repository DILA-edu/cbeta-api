# Convert for Download

## Figures

從 <https://github.com/cbeta-git/CBR2X-figures> 取得圖檔放在 data/figures

## 含別名的作譯者清單

* 產生 data/all-creators-with-alias.json, 供匯出。
* 要從 GitHub 更新 Authority-Databases
* 要在 `rake import:creators` 之後執行，才能判斷別名是否出現在作譯者。

    rake create:creators

## 產生供下載用的 HTML 檔

讀取 CBETA XML P5a, 每一卷都產生一個 HTML 檔
先暫存在 data/html-for-download-tmp, 再移到 public/download/html

執行全部 (假設發行日期為 2019-10) 約需 14分鐘

    rake convert:x2h4d[2020-11]

執行某部藏經（例如：大正藏）

    rake convert:x2h4d[2020-11,T]

## 產生供下載用的 Text 檔

讀取 CBETA XML P5a, 每一卷都產生一個 Text 檔, 再壓縮為 zip 檔
如果有圖檔，也會包在 zip 檔裡。

整部典籍也包成一個 zip 檔。

先暫存在 data/text-for-download-tmp, 再移到 public/download/text

執行全部 (假設發行日期為 2020-01) 大約需時13分鐘

    rake convert:x2t4d[2020-01]

執行某部藏經（例如：大正藏）

    rake convert:x2t4d[2020-01,T]

全部 text 壓縮成一個 zip 檔

    cd public/download
    ln -s text-for-asia-network cbeta-text
    zip -r -X temp.zip cbeta-text
    mv temp.zip cbeta-text.zip

## 產生供 DocuSky 使用的 DocuXML 檔

讀取 CBETA XML P5a, 產生 DocuXml 格式，供 Docusky 使用。

要先準備好

    data/places.json

執行全部大約需時16分鐘

    rake convert:docusky

執行某部藏經（例如：大正藏）

    rake convert:docusky[T]

以上程式會將輸出先暫存在 data/docusky-tmp, 再移到 public/download/docusky

## Footnotes for download

在「產生 xml for sphinx」時一起做，參考 sphinx-build-index.md。
