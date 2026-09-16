desc "每季執行"
task :quarterly => :environment do |_t, _args|
  require_relative 'quarterly/quarterly'
  Quarterly.new.run
end
