namespace :convert do
  desc "XML 轉 下載用 Text"
  task :x2t4d, [:publish, :canon] => :environment do |t, args|
    ConvertX2tForDownload.new.convert(args[:publish], args[:canon])
  end
end

require_relative '../x2t_for_download'

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
      out2: Rails.root.join('public', 'download', 'text-for-asia-network')
    }
    x2t = P5aToTextForDownload.new(args)
    x2t.convert(canon)
    
    dest = File.join(Rails.configuration.cb.dl, 'text')
    FileUtils.rmtree(dest)
    
    puts "move #{tmpdir} => #{dest}"
    FileUtils.mv tmpdir, dest

    puts ElapsedTime.label(t1)
  end
end
