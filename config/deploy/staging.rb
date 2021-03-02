server 'cbdata.dila.edu.tw', user: 'ray', roles: %w{web}
set :deploy_to, '/var/www/cbdata15'

# deploy current branch
# 參考: https://stackoverflow.com/questions/1524204/using-capistrano-to-deploy-from-different-git-branches
set :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }