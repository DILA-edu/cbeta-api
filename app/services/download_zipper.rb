# frozen_string_literal: true

require 'zip'

# 把 public/download/<format>/<canon>/<work>/ 底下的檔案打包成 <canon>/<work>.zip
#
#   DownloadZipper.new(:odt).zip
class DownloadZipper
  def initialize(format)
    @format = format.to_s
    @root = Rails.root.join('public/download', @format)
  end

  def zip
    return puts "找不到 #{@root}" unless @root.exist?

    @root.each_child do |child|
      next unless child.directory?

      zip_canon(child)
    end
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
    work = work_path.basename('.*')
    dest_zip_path = @canon_path.join("#{work}.zip")
    puts dest_zip_path

    Zip::File.open(dest_zip_path, create: true) do |zipfile|
      work_path.glob("*.#{@format}").each do |path|
        zipfile.add(File.join(work.to_s, path.basename.to_s), path)
      end
    end
  end
end
