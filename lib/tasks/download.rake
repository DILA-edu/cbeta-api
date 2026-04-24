namespace :download do
  
  desc "下載電子書"
  task :ebooks, [:type] => :environment do |t, args|
    t1 = Time.now
    require "tasks/download_ebooks"
    DownloadEbooks.new.run(args[:type])
    puts "下載電子書 "
    puts ElapsedTime.label(t1)
  end
end
