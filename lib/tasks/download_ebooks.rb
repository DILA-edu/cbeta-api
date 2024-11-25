class DownloadEbooks
  BASE = "https://archive.cbeta.org/download"
  
  def initialize
    @q = Rails.configuration.cb.r.downcase

    conn = Faraday.new(BASE) { |f| f.response :json }
    @remote_files = conn.get('ebooks.json').body
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

    remote_path = @remote_files[type]
    remote_fn = File.basename(remote_path)
    remote_bn = File.basename(remote_fn, '.*')

    if go
      download("#{BASE}/#{remote_path}")
      File.rename(remote_fn, dest)
    end
    
    fn = "cbeta-#{type}-#{@q}.zip"
    if exec("unzip #{fn} -d tmp")
      exec("rm -rf #{type}")
      d = "tmp/#{remote_bn}"
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
    remote_paths = @remote_files['pdf']
    basenames = []
    remote_paths.each do |remote_path|
      download("#{BASE}/#{remote_path}")
      fn = File.basename(remote_path)
      File.rename(fn, "cbeta-pdf-#{@q}-#{i}.zip")
      exec("unzip cbeta-pdf-#{@q}-#{i}.zip")
      basenames << File.basename(fn, '.*')
    end

    exec("rm -rf pdf")
    exec("mkdir pdf")
    basenames.each do |f|
      exec("mv #{f}/* pdf")
      exec("rm -r #{f}")
    end
  end

  def exec(cmd)
    puts cmd
    system(cmd)
  end
end
