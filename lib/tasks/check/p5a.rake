namespace :check do
  desc "檢查 CBETA xml p5a"
  task :p5a => :environment do
    CBETA::P5aChecker.new(
      xml_root: Rails.configuration.cbeta_xml,
      figures: Rails.configuration.x.figures,
      log: Rails.root.join('log', 'check_p5a.log')
    ).check
  end
end
