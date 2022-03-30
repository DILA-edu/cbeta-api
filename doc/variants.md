# 異體字

## 由 CBETA 缺字庫 更新 異體字 到 metadata

* update cbeta_gaiji from GitHub
* 根據 <https://gitlab.com/dilada/variants> 說明 產生 vars-for-cbdata.json
* 將 vars-for-cbdata.json 更新到 <https://github.com/DILA-edu/cbeta-metadata/tree/master/variants>

## 匯入

1. Update metatada from GitHub.
2. 啟動 sphinx
3. 由 cbeta-metadata/variants/variants.txt 匯入資料到 model: Variant，執行

    bundle exec rake import:vars
