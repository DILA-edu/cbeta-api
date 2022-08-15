# config valid only for current version of Capistrano
lock '3.16.0'

set :application, 'cbapi4'
set :repo_url, 'git@github.com:DILA-edu/cbeta-api.git'

# deploy current branch
# 參考: https://stackoverflow.com/questions/1524204/using-capistrano-to-deploy-from-different-git-branches
set :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }

# Default deploy_to directory is /var/www/my_app_name
# set :deploy_to, '/var/www/my_app_name'

# Default value for :log_level is :debug
# set :log_level, :debug

append :linked_files, "config/master.key", "config/database.yml"
append :linked_dirs, 'data', 'public/download', 'public/help', 'config/credentials'

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