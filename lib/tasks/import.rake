namespace :import do  
  task :canons => :environment do
    require "tasks/import_canons"
    importer = ImportCanons.new
    importer.import
  end
  
  desc "匯入部類目錄"
  task :catalog, [:arg1] => :environment do |t, args|
    require "tasks/import_catalog"
    importer = ImportCatalog.new
    importer.import args[:arg1]
  end
  
  desc "匯入 CBETA 部類"
  task :category => :environment do
    require "tasks/import_category"
    importer = ImportCategory.new
    importer.import
  end
    
  desc "匯入佛典跨冊資訊"
  task :cross => :environment do
    require "tasks/import_cross"
    importer = ImportCross.new
    importer.import
  end

  task :gaiji => :environment do
    require "tasks/import_gaiji"
    importer = ImportGaiji.new
    importer.import
  end
  
  task :goto_abbrs => :environment do
    require "tasks/import_goto_abbrs"
    importer = ImportGotoAbbrs.new
    importer.import
  end
  
  task :jinglu_editors => :environment do
    require "tasks/import_jinglu_editors"
    importer = ImportJingluEditors.new
    importer.import
  end
  
  task :juanline => :environment do
    require "tasks/import_juan_line"
    importer = ImportJuanLine.new
    importer.import
  end
  
  # 可以指定 某一部佛典
  # 例如： bundle exec rake 'import:layers[GA090n0089]'
  task :layers, [:arg1] => :environment do |t, args|
      require "tasks/import_layers"
    importer = ImportLayers.new
    importer.import args[:arg1]
  end

  task :lb_maps => :environment do
    require "tasks/import_lb_maps"
    importer = ImportLbMaps.new
    importer.import
  end
  
  task :lines, [:arg1] => :environment do |t, args|
    require "tasks/import_lines"
    importer = ImportLines.new
    importer.import args[:arg1]
  end  
  
  desc "匯入 各部佛典的翻譯地點 及 地理資訊"
  task :place => :environment do
    require "tasks/import_place"
    importer = ImportPlace.new
    importer.import
  end
  
  desc "匯入 同義詞"
  task :synonym => :environment do
    require "tasks/import_synonym"
    importer = ImportSynonym.new
    importer.import
  end
  
  desc "匯入 佛典內目次"
  task :toc, [:arg1] => :environment do |t, args|
    require "tasks/import_toc"
    importer = ImportToc.new
    importer.import args[:arg1]
  end
  
  desc "匯入 異體字表"
  task :vars => :environment do
    require "tasks/import_vars"
    importer = ImportVars.new
    importer.import
  end
  
  # 改由 import:work_info 執行
  # desc "匯入佛典編號"
  # task :work_id, [:arg1] => :environment do |t, args|
  #   require "tasks/import_work_id"
  #   importer = ImportWorkId.new
  #   importer.import args[:arg1]
  # end
  
  desc "匯入經名、卷數、作譯者"
  task :work_info => :environment do
    require "tasks/import_work_info"
    importer = ImportWorkInfo.new
    importer.import
  end
end
