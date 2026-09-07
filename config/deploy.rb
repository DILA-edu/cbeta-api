# config valid only for current version of Capistrano
lock '3.20.1'

set :repo_url, 'git@github.com:DILA-edu/cbeta-api.git'

# 應用程式名稱不隨環境變化，故放在共用檔。
# 環境的區分由 stage 名稱（cap production / cap staging）與 deploy_to 表達。
set :application, 'cbeta-api'

# deploy current branch
# 參考: https://stackoverflow.com/questions/1524204/using-capistrano-to-deploy-from-different-git-branches
set :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }

# Default deploy_to directory is /var/www/my_app_name
# set :deploy_to, '/var/www/my_app_name'

# Default value for :log_level is :debug
# set :log_level, :debug

append :linked_files, "config/master.key", "config/database.yml", "config/cb.yml"
append :linked_dirs, 'data', 'log', 'public/download', 'public/help', 'config/credentials'

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
# set :keep_releases, 5

set :passenger_restart_with_touch, true

namespace :deploy do
  namespace :check do
    before :linked_files, :set_master_key do
      on roles(:app), in: :sequence, wait: 10 do
        unless test("[ -f #{shared_path}/config/master.key ]")
          upload! 'config/master.key', "#{shared_path}/config/master.key"
        end
      end
    end
  end
end

namespace :deploy do
  task :restart do
    on roles(:web), in: :sequence do
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end
end

# deploy_to 指向角色 symlink，「現在誰是 production」在版控裡看不到，
# 所以提供一支 task 直接問伺服器。見 doc/annual-rotation.md。
#
#   cap production slot:which
#   cap staging slot:which
namespace :slot do
  desc '顯示本 stage 的角色 symlink 實際指向哪一個 slot'
  task :which do
    on roles(:app) do
      real = capture(:readlink, '-f', fetch(:deploy_to)).strip
      info "#{fetch(:stage)}: #{fetch(:deploy_to)} -> #{real}"
    end
  end
end
