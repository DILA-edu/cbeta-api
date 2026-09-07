# deploy_to 指向「角色 symlink」而非 slot 編號（cbapi1/2/3）。
# 年度輪替時只改伺服器上的 symlink，版控裡這個檔案不用動。
# 見 doc/annual-rotation.md。
server 'sakya.dila.edu.tw', user: 'ray', roles: %w{app db web}
set :deploy_to, '/var/www/cbeta-api-production'
