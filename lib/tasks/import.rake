namespace :import do
  task :alt => :environment do
    require "tasks/import_alt"
    importer = ImportAlt.new
    importer.import
  end
  
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
  
  desc "匯入作譯者資訊"
  task :creators, [:arg1] => :environment do |t, args|
    require "tasks/import_creators"
    importer = ImportCreators.new
    importer.import args[:arg1]
  end
  
  desc "匯入典籍跨冊資訊"
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
  
  task :layers => :environment do
    require "tasks/import_layers"
    importer = ImportLayers.new
    importer.import
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
  
  desc "匯入 各部典籍的翻譯地點 及 地理資訊"
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

  desc "匯入 朝代、年代"
  task :time => :environment do
    require "tasks/import_time"
    importer = ImportTime.new
    importer.import
  end
  
  desc "匯入 典籍內目次"
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
  
  desc "匯入典籍編號"
  task :work_id, [:arg1] => :environment do |t, args|
    require "tasks/import_work_id"
    importer = ImportWorkId.new
    importer.import args[:arg1]
  end
  
  desc "匯入經名、卷數、作譯者"
  task :work_info => :environment do
    require "tasks/import_work_info"
    importer = ImportWorkInfo.new
    importer.import
  end
end