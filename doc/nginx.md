# Nginx

## config

編輯 /etc/nginx/sites-available/cbdata.dila

    location ~ ^/dev(/.*|$) {
      alias /var/www/cbdata13/current/public$1;  # <-- be sure to point to 'public'!
      passenger_base_uri /dev;
      passenger_app_root /var/www/cbdata13/current;
      passenger_document_root /var/www/cbdata13/current/public;
      passenger_enabled on;
      passenger_ruby /home/ray/.rvm/gems/ruby-2.7.2@cbdata13/wrappers/ruby;
      gzip            on;
      gzip_min_length 1k;
      gzip_types      text/plain text/javascript application/javascript;
    }

執行以下命令可以得知 passenger_ruby 路徑：
    cd /var/www/cbdata14/current
    passenger-config --ruby-command

## 測試版、正式版 指向同一個 rails project

參考 Passenger 的 參數 passenger_app_group_name 說明：
<https://www.phusionpassenger.com/library/config/nginx/reference/#passenger_app_group_name>

## 重新啟動 nginx

    sudo service nginx restart

測試連結 <http://cbdata.dila.edu.tw/dev>
