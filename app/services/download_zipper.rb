# frozen_string_literal: true

require 'zip'

# 把 public/download/<format>/<canon>/<work>/ 底下的檔案打包成 <canon>/<work>.zip
#
#   DownloadZipper.new(:odt, bundle: true).zip
#
# bundle: true 時另外產生全套打包檔 public/download/cbeta-<format>.zip
class DownloadZipper
  def initialize(format, bundle: false, download_dir: Rails.root.join('public/download'),
                 release: Rails.configuration.cb.r.downcase, catalog_dir: Rails.configuration.x.work_info)
    @format = format.to_s
    @download_dir = Pathname.new(download_dir)
    @root = @download_dir.join(@format)
    @bundle = bundle
    @release = release
    @catalog_dir = catalog_dir
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

  # 全套打包檔, 內部路徑為 cbeta_<format>_<季別>/<canon>/<work>/<檔名>
  # 最上層資料夾帶季別, 與 epub (cbeta_epub_2026r2), pdf (cbeta_pdf_1_2026r2) 的慣例一致,
  # 使用者解壓後才不會拿到一個叫 docx 的通用名稱。
  def zip_bundle
    dest = @download_dir.join("cbeta-#{@format}.zip")
    files = @root.glob("**/*.#{@format}").sort
    root = "cbeta_#{@format}_#{@release}"
    puts "#{dest} (#{files.size} 檔, 內部路徑 #{root}/)"

    write_zip(dest) do |zip|
      add_filelist(zip, root, files)
      files.each { |path| add_entry(zip, path, File.join(root, path.relative_path_from(@root).to_s)) }
    end
  end

  # 經號對照表, 位置與 epub, pdf 一致: 與 <canon> 同層。
  # 只收錄這次打包進去的經號, 檔名的季別與最上層資料夾相同, 下載者才能從資料夾名推出檔名。
  def add_filelist(zip, root, files)
    work_ids = files.map { |path| path.relative_path_from(@root).each_filename.to_a[1] }.uniq
    zip.put_next_entry(File.join(root, "filelist_#{@release}.txt"))
    zip.write(DownloadFilelist.new(work_ids, catalog_dir: @catalog_dir).to_s)
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
