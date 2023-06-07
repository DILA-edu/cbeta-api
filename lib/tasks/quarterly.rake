desc "每季執行"
task :quarterly => :environment do |t, args|
  require_relative 'quarterly/quarterly'
  Quarterly.new.run
end
