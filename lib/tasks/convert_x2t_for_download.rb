require 'chronic_duration'
require_relative 'x2t_for_download'

class ConvertX2tForDownload
    
  def convert(publish, canon)
    t1 = Time.now
    xml_root = Rails.application.config.cbeta_xml

    tmpdir = Rails.root.join('data', 'text-for-download-tmp')
    txt_root = Rails.root.join('public', 'download', 'text-for-asia-network')
    
    x2t = P5aToTextForDownload.new(publish, xml_root, tmpdir, txt_root)
    x2t.convert(canon)
    
    src = tmpdir
    dest = Rails.root.join('public', 'download', 'text')
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