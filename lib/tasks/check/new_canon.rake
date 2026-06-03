namespace :check do  
  desc "檢查 HTML for UI"
  task :new_canon => :environment do
    CheckNewCanon.new.check
  end
end

class CheckNewCanon
  def check
    print "check new canon..."
    @base = Rails.configuration.cb.git

    path = File.join(@base, 'cbeta-metadata', 'canons.yml')
    canons = YAML.load_file(path)

    path = File.join(@base, 'cbeta-xml-p5a')
    new_canon = []
    each_canon(path) do |c|
      next if canons.key?(c)
      new_canon << c
    end

    if new_canon.empty?
      puts "done."
    else
      puts "發現新藏經編號：" + new_canon.join(',')
      puts "必須更新 cbeta metadata, 請參考 doc/new-canon.md"
      raise "Check new canon 發現錯誤"
    end    
  end

  include CbetaP5aShare
end
