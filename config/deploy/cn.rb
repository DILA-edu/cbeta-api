server 'cbetaonline.cn', user: 'ray', roles: %w{web}
set :deploy_to, '/mnt/CBETAOnline/cbdata'

# deploy current branch
# 參考: https://stackoverflow.com/questions/1524204/using-capistrano-to-deploy-from-different-git-branches
set :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }