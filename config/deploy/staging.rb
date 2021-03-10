server 'sakya.dila.edu.tw', user: 'ray', roles: %w{app db web}
set :deploy_to, '/var/www/cbapi1'

# deploy current branch
# 參考: https://stackoverflow.com/questions/1524204/using-capistrano-to-deploy-from-different-git-branches
set :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }