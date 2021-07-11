class DownloadEbooks
  BASE = "https://archive.cbeta.org/download"
  def initialize
    @q = Rails.configuration.x.q
  end

  def run
    dest_folder = Rails.join('public', 'download')
    Dir.chdir(dest_folder) do
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

      download("#{BASE}/mobi/cbeta_mobi_#{@q}.zip")
      File.rename("cbeta_mobi_#{@q}.zip", "cbeta-mobi-#{@q}.zip")
      system "unzip cbeta-mobi-#{@q}.zip"
      system "mv cbeta_mobi_#{@q} mobi"
    end
  end

  private

  def download(url)
    dest_folder = Rails.join('public', 'download')
    Dir.chdir(dest_folder) do
      cmd = "curl -C - -O #{url}"
      i = 1
      loop do
        puts "#{i} ----------"
        puts(cmd)
        break if system(cmd)
      end
    end
  end
end