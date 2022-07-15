namespace :download do
  
  desc "下載電子書"
  task :ebooks, [:type] => :environment do |t, args|
    require "tasks/download_ebooks"
    c = DownloadEbooks.new.run(args[:type])
  end
end