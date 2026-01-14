namespace :create do
  desc "產生 全部佛典 卷列表"
  task :all_works_list => :environment do
    require "tasks/create_all_works_list"
    CreateAllWorksList.new.create
  end

  desc "產生 嘉興藏檢查表"
  task :check_list_j => :environment do
    require "tasks/create_check_list_j"
    CreateCheckListJ.new.create
  end

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

  desc "產生 供 UI 使用的 範圍選擇清單"
  task :scope_selector => :environment do
    require "tasks/create_scope_selector"
    c = CreateScopeSelector.new
    c.create
  end
end
