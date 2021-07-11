namespace :download do
  
  desc "下載電子書"
  task :ebooks => :environment do
    require "tasks/download_ebooks"
    c = DownloadEbooks.new.run
  end
