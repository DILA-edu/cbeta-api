namespace :convert do  
  desc "XML 轉 下載用 HTML"
  task :x2h4d, [:publish, :canon] => :environment do |t, args|
    c = ConvertX2hForDownload.new
    c.convert(args[:publish], args[:canon])
  end
end

require_relative '../x2h_for_download'

class ConvertX2hForDownload
  def convert(publish, canon)
    t1 = Time.now
    xml_root = Rails.application.config.cbeta_xml

    tmpdir = Rails.root.join('data', 'html-for-download-tmp')
    
    x2h = P5aToHTMLForDownload.new(publish, xml_root, tmpdir)
    x2h.convert(canon)
    
    src = tmpdir
    dest = File.join(Rails.configuration.cb.dl, 'html')
    FileUtils.mkdir_p(dest)
    
    # 備份舊資料
    if Dir.exist? dest
      bak = dest.to_s + '-' + Time.new.strftime("%Y-%m-%d-%H%M%S")
      puts "move #{dest} => #{bak}"
      FileUtils.mv dest, bak
    end
    
    puts "move #{src} => #{dest}"
    FileUtils.mv src, dest
    
    puts ElapsedTime.label(t1)
  end  
end
