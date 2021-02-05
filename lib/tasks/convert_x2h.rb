require 'chronic_duration'
require_relative 'x2h_for_ui'

class ConvertX2h
    
  def convert(publish, canon)
    t1 = Time.now
    xml_root = Rails.application.config.cbeta_xml

    tmpdir = Rails.root.join('data', 'html-tmp')
    
    x2h = P5aToHTMLForUI.new(publish, xml_root, tmpdir)
    x2h.convert(canon)

    unless canon.nil?
      return if canon.size > 2
    end
    
    dest_root = Rails.root.join('data', 'html')
    FileUtils.makedirs dest_root
    
    if canon.nil?
      dest = dest_root
      src = tmpdir
    else
      dest = File.join(dest_root, canon)
      src = File.join(tmpdir, canon)
    end
    
    if Dir.exist? dest
      bak = dest.to_s + '-' + Time.new.strftime("%Y-%m-%d-%H%M%S")
      $stderr.puts "move #{dest} => #{bak}"
      FileUtils.mv dest, bak
    end
    
    $stderr.puts "move #{src} => #{dest}"
    FileUtils.mv src, dest
    
    puts "花費時間：" + ChronicDuration.output(Time.now - t1)
    puts "如果有更新到《佛寺志》，也要記得執行 rake import:layers"
  end
  
end