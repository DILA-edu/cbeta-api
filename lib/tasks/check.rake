namespace :check do
  
  desc "檢查電子書封面是否都存在"
  task :covers => :environment do
    require "tasks/check_covers"
    CheckCover.new.check
  end

  desc "檢查 xml p5a 裡的缺字是否在 cbeta gem 之中都有缺字資訊"
  task :gaiji => :environment do
    require "tasks/check_gaiji"
    CheckGaiji.new.check
  end
  
  task :metadata => :environment do
    require "tasks/check_metadata"
    CheckMetadata.new.check
  end

  desc "檢查 CBETA xml p5a"
  task :p5a => :environment do
    CBETA::P5aChecker.new(
      xml_root: Rails.configuration.cbeta_xml,
      figures: Rails.configuration.x.figures,
      log: Rails.root.join('log', 'check_p5a.log')
    ).check
  end
end
