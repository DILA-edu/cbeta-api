# 建立 server 測試環境

編輯 config 參數

* config/application.rb
* config/deploy/staging.rb
* lib/tasks/quarterly/config.rb

開發端
    cap staging deploy

server 端
    screen
    rake quarterly[staging]
