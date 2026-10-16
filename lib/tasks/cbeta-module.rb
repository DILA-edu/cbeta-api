require 'open3'

module CBETAModule
  # XML 檔最後一次 commit 的日期 (committer date, 本機時區, YYYY-MM-DD)。
  # path: 相對於 XML repo 的路徑，或 repo 內的絕對路徑。
  def cb_xml_updated_at(path: nil)
    path = path || "#{@canon}/#{@vol}/#{@sutra_no}.xml"
    # 兩邊都解開 symlink 再比較 (例如 macOS 的 /var → /private/var)
    root = Pathname.new(@git.dir.path).realpath
    rel = Pathname.new(path).absolute? ? Pathname.new(path).realdirpath.relative_path_from(root).to_s : path

    date = cb_xml_updated_dates(root)[rel]
    abort "取得 git log 發生錯誤, path: #{path}" if date.nil?
    date
  end

  private

  # 一次 git log 建好「路徑 => 最後 commit 日期」。
  #
  # 原本每個檔案各跑一次 @git.log.path(path).first (spawn 一次 git)，
  # 五千多個 XML 檔要 2 分鐘 (本機)，x2h4d、x2t4d 等每個轉檔 task 都要付一次。
  #
  # 與逐檔查詢等價 (2026-10-16 對全部 5034 個 XML 檔比對相同):
  #   * ruby-git 的 Commit#date 是 committer date，以 Time.at(epoch) 轉本機時區，這裡用 %ct 同樣處理
  #   * git log 由新到舊，第一次出現的就是最後一次 commit
  #   * -c: merge commit 只列出與每個 parent 都不同的檔案，對應 path-limited git log
  #     在 history simplification 下會顯示該 merge 的條件
  def cb_xml_updated_dates(root)
    @cb_xml_updated_dates ||= begin
      out, status = Open3.capture2('git', '-C', root.to_s, 'log', '-c', '--name-only', '--format=%x01%ct')
      abort "取得 git log 發生錯誤: #{root}" unless status.success?

      map = {}
      date = nil
      out.each_line(chomp: true) do |line|
        if line.start_with?("\x01")
          date = Time.at(line[1..].to_i).strftime('%Y-%m-%d')
        elsif !line.empty?
          map[line] ||= date
        end
      end
      map
    end
  end
end
