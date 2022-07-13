namespace :custom do
  # 停用，完全按照 authority 的資料
  task :compare_creators => :environment do
    require_relative 'diff-creators'
    DiffCreators.diff
  end
end
