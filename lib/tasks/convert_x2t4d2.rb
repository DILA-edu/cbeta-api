require 'chronic_duration'
require_relative 'x2t_for_download'

# Convert XML to Text for Download (含校注)
class ConvertX2T4D2    
  def convert(publish, canon)
    t1 = Time.now
    xml_root = Rails.application.config.cbeta_xml

    tmpdir = Rails.root.join('data', 'text-for-download-tmp')    
    args = {
      format: 'text',
      notes: true, # 指定要含校注
      publish: publish,
      xml_root: Rails.application.config.cbeta_xml,
      out_root: tmpdir,
      # out2: 供壓縮為 cbeta-text-with-notes.zip
      out2: Rails.root.join('data', 'download', 'cbeta-text-with-notes')
    }
    x2t = P5aToTextForDownload.new(args)
    x2t.convert(canon)
    
    dest = Rails.root.join('data', 'download', 'text-with-notes')
    FileUtils.mkdir_p(dest)
    
    # 備份舊資料
    if Dir.exist? dest
      bak = dest.to_s + '-' + Time.new.strftime("%Y-%m-%d-%H%M%S")
      puts "move #{dest} => #{bak}"
      FileUtils.mv dest, bak
    end
    
    puts "move #{tmpdir} => #{dest}"
    FileUtils.mv tmpdir, dest

    puts "花費時間：" + ChronicDuration.output(Time.now - t1)
  end
  
end
