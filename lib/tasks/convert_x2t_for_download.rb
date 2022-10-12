require 'chronic_duration'
require_relative 'x2t_for_download'

class ConvertX2tForDownload
    
  def convert(publish, canon)
    t1 = Time.now

    tmpdir = Rails.root.join('data', 'text-for-download-tmp')
    args = {
      format: 'text',
      notes: false, # 不含校注
      publish: publish,
      xml_root: Rails.application.config.cbeta_xml,
      out_root: tmpdir,
      out2: Rails.root.join('data', 'download', 'text-for-asia-network')
    }
    x2t = P5aToTextForDownload.new(args)
    x2t.convert(canon)
    
    src = tmpdir
    dest = Rails.root.join('data', 'download', 'text')
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
