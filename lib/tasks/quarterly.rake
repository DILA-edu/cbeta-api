namespace :quarterly do
  desc "每季執行"
  task :run, [:env] => :environment do |t, args|
    require_relative 'quarterly'
    Quarterly.new(args[:env]).run
  end

  task :view, [:env] => :environment do |t, args|
    require_relative 'quarterly'
    Quarterly.new(args[:env]).view
  end
end