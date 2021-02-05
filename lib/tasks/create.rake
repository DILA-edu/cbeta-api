namespace :create do
  
  desc "產生 含別名的 作譯者清單"
  task :creators => :environment do
    require "tasks/create_creators"
    c = CreateCreatorsList.new
    c.create
  end

  desc "產生 UUID"
  task :uuid => :environment do
    require "tasks/create_uuid"
    c = CreateUuid.new
    c.create
  end  
end