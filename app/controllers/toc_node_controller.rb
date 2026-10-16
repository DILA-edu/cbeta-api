class TocNodeController < ApplicationController  
  include ApiKeyAuthentication
  include TocNodeHelper

  def index
    # q 為 nil 或空字串時, search_by_query_term 的 else 分支會變成
    # LIKE '%%' 全表掃描 (catalog + work + toc 三張表, 且每筆再查一次 work info),
    # 實測會跑滿 rack-timeout 的 300 秒並佔住一個 Passenger process。
    if params[:q].blank?
      my_render(num_found: 0, results: [], error: '缺少 q 參數')
      return
    end

    # 限制查詢字串長度（字數）
    if query_too_long?(params[:q])
      my_render(num_found: 0, results: [], error: query_length_error)
      return
    end

    start = Time.now
    result = search_by_query_term
    return if performed? # 冊號查詢已 redirect 到 catalog_entry

    result = [] if result.nil?

    result.each do |r|
      if r.key?(:work) and r.key?(:file) and r.key?(:lb)
        r[:linehead] = get_linehead(r[:work], r[:file], r[:lb])
      end
    end

    r = {
      num_found: result.size,
      time: Time.now - start,
      results: result
    }

    my_render(r)
  end
  
  private
  
  def find_catalog(q)
    # 沒有 ORDER BY 時 PostgreSQL 不保證順序; id 是匯入時的目錄順序
    entries = CatalogEntry.where("(label NOT LIKE '%=%') AND (label LIKE ?)", "%#{q}%").order(:id)
    r = []
    entries.each do |e|
      row = { type: 'catalog', n: e.n, label: e.label }
      unless e.work.nil?
        work_info = work_info(e.work)
        row.merge! work_info
      end
      r << row
    end
    r
  end
  
  def find_toc(q)
    # 同一部佛典的節點 sort_order 相同, 只排 sort_order 時每次查詢的順序都可能不同;
    # id 是匯入時的文件順序
    toc_nodes = TocNode.where("label LIKE ?", "%#{q}%").order(:sort_order, :id)
    r = []
    toc_nodes.each do |t|
      row = { type: 'toc', label: t.label, label_path: label_path(t), work: t.work, lb: t.lb }
      w = work_info(t.work)
      if w.nil?
        # 這裡原本是 abort, 在 Passenger worker 裡會直接殺掉整個 process。
        logger.fatal "Error get_info_by_id(#{t.work})"
        next
      end
      row.merge! w
      row[:file] = t.file
      row[:juan_start] = t.juan
      r << row
    end
    r
  end
  
  def find_work(q)
    works = Work.where.not(juan_list: nil) # CBETA 未收錄的不要
    works = works.where("title LIKE ?", "%#{q}%").order(:sort_order, :id).includes(:places)
    r = []
    works.each do |w|
      row = { type: 'work' }
      row.merge! w.to_hash
      r << row
    end
    r
  end
  
  # 同一部佛典常有上百個目次節點 (例: q=金剛 1042 筆只來自 343 部),
  # 原本每個節點都重查一次。結果與逐筆呼叫 Work.get_info_by_id 相同。
  # 回傳的 Hash 會被多筆 row merge!, 但不會被修改。
  def work_info(n)
    @work_info ||= Hash.new { |h, key| h[key] = Work.get_info_by_id(key) }
    @work_info[n]
  end

  # 目次的完整路徑: 由 import:toc 走訪時算好存在 label_path 欄位。
  # 欄位為空 (2026-10-16 加欄位後尚未重新匯入) 時才沿 parent 逐層查,
  # parent 查過的不再查。注意以 n 反查 parent 在 n 重複時 (例 B0002) 可能接錯祖先。
  def label_path(node)
    return node.label_path if node.label_path.present?

    @toc_parent ||= Hash.new { |h, n| h[n] = TocNode.find_by(n:) }
    tokens = []
    t = node
    until t.nil?
      tokens.unshift t.label
      t = @toc_parent[t.parent]
    end
    tokens.join('/')
  end

  def search_by_query_term
    q = params[:q]
    if q.match(/^(#{CBETA::CANON})\d{2,3}$/) # ex: T01
      ce = CatalogEntry.find_by_vol(q)
      return [] if ce.nil?

      # 呼叫端 (index) 看到 performed? 就不再 render
      redirect_to controller: 'catalog_entry', action: 'index', q: ce.n
      return
    elsif q.match(/^(#{CBETA::CANON})\d{2,3}n(\w{4,5})$/) # ex: T01n0001
      q = $1 + $2
      w = Work.find_by n: q
      return [] if w.nil?

      row = { type: 'work' }
      row.merge! w.to_hash
      result = [row]
    elsif q.match(CBETA::WORK_ID) # ex: T0001, JB271, ZWa073
      works = Work.where("n LIKE ?", "#{q}%")
      result = []
      works.each do |w|
        row = { type: 'work' }
        row.merge! w.to_hash
        result << row
      end
    else
      result = find_catalog(q)
      result.concat(find_work(q))
      result.concat(find_toc(q))
    end
    result
  end

end
