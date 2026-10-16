namespace :convert do  
  desc "XML 轉 Change Log 比對用 Text Normal 版"
  task :x2t, [:q] => :environment do |_t, args|
    # 路徑與季度流程的 change log 步驟相同 (lib/tasks/quarterly/config.rb, 依環境而定)
    require_relative '../quarterly/config'
    config = Object.new.extend(Config).get_config
    v = args[:q] # 例: 2021Q1
    dest = File.join(config[:change_log], "cbeta-normal-#{v}")
    require_relative '../quarterly/p5a_to_text'
    c = P5aToText.new(config[:xml], dest, gaiji_base: config[:gaiji])
    c.convert
  end
end
