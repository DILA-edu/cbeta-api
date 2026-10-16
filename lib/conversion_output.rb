require 'fileutils'

# 轉檔 rake 的輸出目錄處理: 先轉到 tmpdir, 完成後再放到 dest。
module ConversionOutput
  module_function

  # 全部轉檔 (partial: false): 以 tmpdir 整個取代 dest。
  # 只轉部分 (partial: true, 例如指定 canon 或冊): 把 tmpdir 合併進 dest,
  # 保留其他部分的既有輸出。過去一律先清空 dest, 會讓 dest 只剩這次轉的部分。
  def install(tmpdir, dest, partial:)
    if partial
      puts "merge #{tmpdir} => #{dest}"
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(File.join(tmpdir, '.'), dest)
      FileUtils.rmtree(tmpdir)
    else
      FileUtils.rmtree(dest)
      puts "move #{tmpdir} => #{dest}"
      FileUtils.mv(tmpdir, dest)
    end
  end
end
