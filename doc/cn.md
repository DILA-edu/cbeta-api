# cbetaonline.cn

## xml 更新特定 tag

    cd /mnt/CBETAOnline/git-repos/cbeta-xml-p5a
    git pull
    git checkout tags/2021Q1

## 半自動 runbook

  rake quarterly_cn

## 電子書

    curl -C - -O http://cbdata.dila.edu.tw/dev/download/cbeta-epub-2020q4.zip
    curl -C - -O http://cbdata.dila.edu.tw/dev/download/cbeta-mobi-2020q4.zip
    
    curl -C - -O http://cbdata.dila.edu.tw/dev/download/cbeta-pdf-2020q4-1.zip
    unzip cbeta-pdf-2020q4-1.zip

    curl -C - -O http://cbdata.dila.edu.tw/download/cbeta-pdf-2020q4-2.zip

續傳

    curl -C - -O [URL]

curl Options

-O, --remote-name   Write output to a file named as the remote file
-C, --continue-at OFFSET  Resumed transfer OFFSET

## Sphinx

    sudo indexer --rotate cbeta7

## secret_key_base

    EDITOR="code --wait" bin/rails credentials:edit --environment cn

上面命令會做以下動作：

* 建立 config/credentials/cn.key 如果沒有的話。這個檔不要送上 Git.
* 建立 config/credentials/cn.yml.enc 沒果沒有的話。這個檔要送上 Git.
* 解碼並使用編輯器 code 開啟 cn credentials 檔案。
