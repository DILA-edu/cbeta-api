# xml for docx

執行 rake convert:xml4docx,
或依序執行以下步驟：

1. xml4docx1
   將 CBETA XML 簡化為適合 docx 使用
   * 全部: `rake 'convert:xml4docx1[2026-03]'`
   * 只做某部藏經: `rake 'convert:xml4docx1[2026-03,T]'`
2. xml4docx2
   將 xml4docx1 結果 做 扁平化 處理，如例：seg 包 seg
   rake 'convert:xml4docx2[T]'
3. check:xml4docx
   檢查 xml4docx 正確性
   rake check:xml4docx
4. 給 heven 比對 text 正確性

## 產生下載檔

xml4docx 可以轉成 docx 與 odt 兩種格式，兩者都是純 Ruby 直接產生，
不需要 Word 或 LibreOffice：

```
rake 'convert:docx[,10]'   # 輸出 public/download/docx
rake 'convert:odt[,10]'    # 輸出 public/download/odt
rake zip:docx              # 一經一個 zip
rake zip:odt               # 一經一個 zip, 另外產生全套的 cbeta-odt.zip
```

`zip:odt` 產生的 `public/download/cbeta-odt.zip` 內部路徑為
`odt/<canon>/<work>/<檔名>.odt`。兩個 task 都是每次重建，可以重複執行。

參數是 `[filter,workers]`，filter 會比對來源路徑（例如 `T01`），
省略則全部重轉並先清空輸出目錄；workers 預設為 CPU 核心數。
全量 14047 檔在 10 個 process 下約 20 秒。

轉檔邏輯：

* `XmlToDocxConverter` — 產生 OOXML
* `XmlToOdtConverter` — 產生 ODF
* `Xml4docxSupport` — 兩者共用的 style 解析、table 跨欄跨列計算、圖片讀取
