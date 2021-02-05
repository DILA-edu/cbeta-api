namespace :custom do
  task :compare_creators => :environment do
    require_relative 'diff-creators'
    DiffCreators.diff
  end
end
