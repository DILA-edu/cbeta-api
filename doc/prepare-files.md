# Prepare Data Files

## Help HTML Files

由 server 上的舊版複製

    cp -r /var/www/cbdata10/shared/public/help /var/www/cbdata11/shared/public

## figures

### cn

    ln -s /mnt/CBETAOnline/git-repos/CBR2X-figures /mnt/CBETAOnline/cbdata/shared/data/figures

## places.json

由 server 上的舊版複製 data/places.json

## juan-line

由 server 上的舊版複製 shared/data/juan-line

如果資料有更新，可使用這裡的程式產生新資料
/Users/ray/Documents/Projects/CBETA/juanline/bin/juanline.rb

## UUID

如果有新增典籍，要產生 UUID，參考 uuid.md

## 自動分詞

data/crf-model/all
