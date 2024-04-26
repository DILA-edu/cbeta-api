class DownloadEbooks
  BASE = "https://archive.cbeta.org/download"
  
  def initialize
    @q = Rails.configuration.cb.r.downcase
  end

  def run(type=nil)
    @errors = ""
    @dest_folder = Rails.root.join('data', 'download')
    Dir.chdir(@dest_folder) do
      case type
      when 'epub', 'mobi'
        download_one_zip(type)
      when 'pdf'
        download_pdf
      else
        download_one_zip('epub')
        download_one_zip('mobi')
        download_pdf
      end
    end
    puts @errors
  end

  private

  def download(url)
    cmd = "curl -C - -O #{url}"
    i = 1
    loop do
      puts "#{i} ----------"
      break if exec(cmd)
    end
  end

  def download_one_zip(type)
    dest = "cbeta-#{type}-#{@q}.zip"

    go = true
    if File.exist?(dest)
      puts "#{dest} 已存在，是否仍要重新下載？"
      print 'Continue? 按 Enter 繼續，按 s 跳過 '
      c = STDIN.getch.chomp
      puts
      go = false if c == 's'
    end

    if go
      download("#{BASE}/#{type}/cbeta_#{type}_#{@q}.zip") 
      File.rename("cbeta_#{type}_#{@q}.zip", dest)
    end
    
    fn = "cbeta-#{type}-#{@q}.zip"
    if exec("unzip #{fn} -d tmp")
      exec("rm -rf #{type}")
      d = "tmp/cbeta_#{type}_#{@q}"
      if Dir.exist?(d)
        exec("mv #{d} #{type}")
        exec("rm -rf tmp")
      else
        exec("mv tmp #{type}")
      end
      true
    else
      @errors << "解壓縮失敗: #{fn}\n"
      false
    end
  end

  def download_pdf
    (1..3).each do |i|
      download("#{BASE}/pdf_a4/cbeta_pdf_#{i}_#{@q}.zip")
      File.rename("cbeta_pdf_#{i}_#{@q}.zip", "cbeta-pdf-#{@q}-#{i}.zip")
      exec("unzip cbeta-pdf-#{@q}-#{i}.zip")
    end

    exec("rm -rf pdf")
    exec("mv cbeta_pdf_1_#{@q} pdf")
    exec("mv cbeta_pdf_2_#{@q}/* pdf")
    exec("mv cbeta_pdf_3_#{@q}/* pdf")
    exec("rm -r cbeta_pdf_2_#{@q}")
    exec("rm -r cbeta_pdf_3_#{@q}")
  end

  def exec(cmd)
    puts cmd
    system(cmd)
  end
end
