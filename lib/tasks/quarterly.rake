namespace :quarterly do
  desc "每季執行"
  task :run => :environment do |t, args|
    require_relative 'quarterly'
    Quarterly.new.run
  end

  task :view => :environment do |t, args|
    require_relative 'quarterly'
    Quarterly.new.view
  end
end
