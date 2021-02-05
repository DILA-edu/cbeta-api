server 'cbetaonline.cn', user: 'ray', roles: %w{web}
set :rvm_ruby_version, '2.7.2@cbdata13'
set :deploy_to, '/mnt/CBETAOnline/cbdata'

# https://github.com/rvm/rvm-capistrano
# :rvm_type - how to detect rvm, default :user
# :user - RVM installed in $HOME, user installation (default)
# :system - RVM installed in /usr/local, multiuser installation
set :rvm_type, :system