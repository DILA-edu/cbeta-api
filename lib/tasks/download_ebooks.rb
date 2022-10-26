class DownloadEbooks
  BASE = "https://archive.cbeta.org/download"
  
  def initialize
    @q = Rails.configuration.x.q
  end

  def run(type=nil)
    @errors = ""
    dest_folder = Rails.root.join('data', 'download')
    Dir.chdir(dest_folder) do
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
      puts(cmd)
      break if system(cmd)
    end
  end

  def download_one_zip(type)
    download("#{BASE}/#{type}/cbeta_#{type}_#{@q}.zip")
    File.rename("cbeta_#{type}_#{@q}.zip", "cbeta-#{type}-#{@q}.zip")
    fn = "cbeta-#{type}-#{@q}.zip"
    if system("unzip #{fn}")
      system "rm -rf #{type}"
      system "mv cbeta_#{type}_#{@q} #{type}"
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
      system "unzip cbeta-pdf-#{@q}-#{i}.zip"
    end

    system "rm -rf pdf"
    system "mv cbeta_pdf_1_#{@q} pdf"
    system "mv cbeta_pdf_2_#{@q}/* pdf"
    system "mv cbeta_pdf_3_#{@q}/* pdf"
    system "rm -r cbeta_pdf_2_#{@q}"
    system "rm -r cbeta_pdf_3_#{@q}"
  end
end
