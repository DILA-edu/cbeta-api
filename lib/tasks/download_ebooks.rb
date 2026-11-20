# https://archive.cbeta.org/download/ebooks.json
#
# 不再停下來詢問（非互動的 quarterly runner 沒有 TTY）：
# 新檔先下載到暫時檔名，完成後才把舊檔備份成 <名稱>-<時間>.zip，新檔換成正式檔名。
# 下載中斷時舊檔不受影響，重跑會從暫時檔續傳。
class DownloadEbooks
  BASE = "https://archive.cbeta.org/download"
  MAX_ATTEMPTS = 10
  RETRY_WAIT = 10 # 秒

  def initialize
    @q = Rails.configuration.cb.r.downcase
    @stamp = Time.now.strftime('%Y-%m-%d-%H%M')

    conn = Faraday.new(BASE) { |f| f.response :json }
    @remote_files = conn.get('ebooks.json').body
  end

  def run(type = nil)
    @errors = ""
    Dir.chdir(Rails.configuration.cb.dl) do
      case type
      when 'epub'
        download_one_zip(type)
      when 'pdf'
        download_pdf
      else
        download_one_zip('epub')
        download_pdf
      end
    end
    puts @errors
    abort @errors unless @errors.empty?
  end

  private

  # 下載到暫時檔名；成功才換成正式檔名，舊檔備份
  def fetch(remote_path, dest)
    tmp = "#{File.basename(remote_path)}.part"
    url = "#{BASE}/#{remote_path}"

    ok = (1..MAX_ATTEMPTS).any? do |i|
      puts "#{i} ----------"
      exec("curl -f -C - -o #{tmp} #{url}") || (sleep(RETRY_WAIT) && false)
    end
    unless ok
      @errors << "下載失敗: #{url}（暫時檔 #{tmp} 保留，重跑可續傳）\n"
      return false
    end

    backup(dest)
    File.rename(tmp, dest)
    true
  end

  # cbeta-epub.zip => cbeta-epub-2026-11-20-0900.zip
  def backup(dest)
    return unless File.exist?(dest)

    ext = File.extname(dest)
    bak = "#{File.basename(dest, ext)}-#{@stamp}#{ext}"
    puts "備份舊檔: #{dest} => #{bak}"
    File.rename(dest, bak)
  end

  def download_one_zip(type)
    dest = "cbeta-#{type}.zip"
    remote_path = @remote_files[type]
    remote_bn = File.basename(remote_path, '.*')

    return false unless fetch(remote_path, dest)

    exec("rm -rf tmp")
    if exec("unzip -q #{dest} -d tmp")
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
      @errors << "解壓縮失敗: #{dest}\n"
      false
    end
  end

  def download_pdf
    remote_paths = @remote_files['pdf']
    basenames = []
    remote_paths.each_with_index do |remote_path, i|
      dest = "cbeta-pdf-#{i + 1}.zip"
      return false unless fetch(remote_path, dest)

      bn = File.basename(remote_path, '.*')
      exec("rm -rf #{bn}")
      unless exec("unzip -q #{dest}")
        @errors << "解壓縮失敗: #{dest}\n"
        return false
      end
      basenames << bn
    end

    exec("rm -rf pdf")
    exec("mkdir pdf")
    basenames.each do |f|
      exec("mv #{f}/* pdf")
      exec("rm -r #{f}")
    end
    true
  end

  def exec(cmd)
    puts cmd
    system(cmd)
  end
end
