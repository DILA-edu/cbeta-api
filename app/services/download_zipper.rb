# frozen_string_literal: true

require 'zip'

# 把 public/download/<format>/<canon>/<work>/ 底下的檔案打包成 <canon>/<work>.zip
#
#   DownloadZipper.new(:odt, bundle: true).zip
#
# bundle: true 時另外產生全套打包檔 public/download/cbeta-<format>.zip
class DownloadZipper
  def initialize(format, bundle: false, download_dir: Rails.root.join('public/download'))
    @format = format.to_s
    @download_dir = Pathname.new(download_dir)
    @root = @download_dir.join(@format)
    @bundle = bundle
  end

  def zip
    return puts "找不到 #{@root}" unless @root.exist?

    @root.each_child do |child|
      next unless child.directory?

      zip_canon(child)
    end

    zip_bundle if @bundle
  end

  private

  def zip_canon(canon_path)
    @canon_path = canon_path
    canon_path.each_child do |child|
      next unless child.directory?

      zip_work(child)
    end
  end

  def zip_work(work_path)
    work = work_path.basename('.*').to_s
    dest = @canon_path.join("#{work}.zip")
    puts dest

    write_zip(dest) do |zip|
      work_path.glob("*.#{@format}").sort.each do |path|
        add_entry(zip, path, File.join(work, path.basename.to_s))
      end
    end
  end

  # 全套打包檔, 內部路徑為 <format>/<canon>/<work>/<檔名>
  def zip_bundle
    dest = @download_dir.join("cbeta-#{@format}.zip")
    files = @root.glob("**/*.#{@format}").sort
    puts "#{dest} (#{files.size} 檔)"

    write_zip(dest) do |zip|
      files.each { |path| add_entry(zip, path, File.join(@format, path.relative_path_from(@root).to_s)) }
    end
  end

  # 每次都重建: 沿用既有的 zip 會在加入同名 entry 時失敗, 重跑就掛。
  # 先寫暫存檔再換上, 使用者也不會下載到寫一半的檔案。
  def write_zip(dest)
    tmp = dest.sub_ext('.zip.tmp')
    tmp.delete if tmp.exist?
    Zip::OutputStream.open(tmp.to_s) { |zip| yield zip }
    tmp.rename(dest.to_s)
  end

  def add_entry(zip, path, entry_name)
    zip.put_next_entry(entry_name)
    zip.write(path.binread)
  end
end
