# Import Layers

## 佛寺志專案 產生 layers 中介檔

fosizhi/ruby/export.rb
產生 csv 檔放到 data/layers/fosizhi

## 要先產生 HTML

    rake convert:x2h[2018-12,GA]

## 匯入 layers

在 HTML 檔 插入 人名、地名 標記

    rake import:layers

上述命令會輸出檔案到 data/html-with-layers
