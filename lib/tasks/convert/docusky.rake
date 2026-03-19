namespace :convert do
  desc "XML 轉 Docusky"
  task :docusky, [:canon] => :environment do |t, args|
    c = ConvertDocusky.new
    c.convert(args[:canon])
  end
end

require 'chronic_duration'
require_relative '../x2x_for_docusky'

class ConvertDocusky    
  def convert(canon)
    t1 = Time.now
    xml_root = Rails.application.config.cbeta_xml

    tmpdir = Rails.root.join('data', 'docusky-tmp')
    
    c = P5aToDocusky.new(xml_root, tmpdir)
    c.convert(canon)
    
    src = tmpdir
    dest = File.join(Rails.configuration.cb.dl, 'docusky')
    FileUtils.mkdir_p(dest)
    
    # 備份舊資料
    if Dir.exist? dest
      bak = dest.to_s + '-' + Time.new.strftime("%Y-%m-%d-%H%M%S")
      puts "move #{dest} => #{bak}"
      FileUtils.mv dest, bak
    end
    
    puts "move #{src} => #{dest}"
    FileUtils.mv src, dest
    
    puts "花費時間：" + ChronicDuration.output(Time.now - t1)
  end
  
end
