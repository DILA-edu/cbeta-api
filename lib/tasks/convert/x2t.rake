namespace :convert do  
  desc "XML 轉 Change Log 比對用 Text Normal 版"
  task :x2t, [:q] => :environment do |t, args|
    v = args[:q] # 例: 2021Q1
    src = Rails.configuration.cbeta_xml
    gaiji = Rails.configuration.cbeta_gaiji
    dest = File.join("/home/ray/cbeta-change-log", "cbeta-normal-#{v}")
    require_relative '../quarterly/p5a_to_text'
    c = P5aToText.new(src, dest, gaiji_base: gaiji)
    c.convert
  end
end
