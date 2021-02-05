require 'chronic_duration'
require_relative 'x2h_for_download'

class ConvertX2hForDownload
    
  def convert(publish, canon)
    t1 = Time.now
    xml_root = Rails.application.config.cbeta_xml

    tmpdir = Rails.root.join('data', 'html-for-download-tmp')
    
    x2h = P5aToHTMLForDownload.new(publish, xml_root, tmpdir)
    x2h.convert(canon)
    
    src = tmpdir
    dest = Rails.root.join('public', 'download', 'html')
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