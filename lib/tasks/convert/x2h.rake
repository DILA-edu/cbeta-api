namespace :convert do  
  desc "XML 轉 HTML"
  # 只轉某部經： rake convert:x2h[2020-09,T10n0297]
  task :x2h, [:publish, :canon] => :environment do |t, args|
    c = ConvertX2h.new
    c.convert(args[:publish], args[:canon])
  end
end

require_relative '../x2h_for_ui'

class ConvertX2h    
  def convert(publish, canon=nil)
    t1 = Time.now
    publish ||= Date.today.strftime("%Y-%m")

    tmpdir = Rails.root.join('data', 'html-tmp')
    args = {
      notes: true,
      publish: publish,
      xml_root: Rails.application.config.cbeta_xml,
      out_root: tmpdir
    }
    x2h = P5aToHTMLForUI.new(args)
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
    
    puts ElapsedTime.label(t1)
    puts "如果有更新到《佛寺志》，也要記得執行 rake import:layers"
  end
  
end
