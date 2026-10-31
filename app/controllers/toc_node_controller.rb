class TocNodeController < ApplicationController  
  include ApiKeyAuthentication
  include TocNodeHelper

  # 結果依這個順序串接: 部類目錄 → 經名 → 目次
  TYPES = %w[catalog work toc].freeze

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

    error = parse_paging_params
    if error
      my_render(num_found: 0, results: [], error:)
      return
    end

    start = Time.now
    result = search_by_query_term
    return if performed? # 冊號查詢已 redirect 到 catalog_entry

    result.each do |r|
      if r.key?(:work) and r.key?(:file) and r.key?(:lb)
        r[:linehead] = get_linehead(r[:work], r[:file], r[:lb])
      end
    end

    r = {
      num_found: @num_found,
      counts: @counts,
      time: Time.now - start,
      results: result
    }

    my_render(r)
  end
  
  private

  # start: 起始位置; rows: 筆數, 未帶時全部回傳 (維持舊行為);
  # type: 只取某幾類, 逗號分隔。格式錯誤時回傳錯誤訊息。
  def parse_paging_params
    @start = 0
    @rows = nil
    @types = TYPES

    %i[start rows].each do |key|
      next unless params.key?(key)
      return "#{key} 參數須為 0 以上的整數" unless params[key].to_s.match?(/\A\d+\z/)

      instance_variable_set("@#{key}", params[key].to_i)
    end

    if params[:type].present?
      types = params[:type].to_s.split(',').map(&:strip).reject(&:empty?)
      invalid = types - TYPES
      return "type 參數不正確: #{invalid.join(',')}; 可用值: #{TYPES.join(', ')}" if invalid.any?

      # 依 TYPES 的順序, 與參數裡的先後無關
      @types = TYPES & types
    end
    nil
  end

  # 依佛典編號直接取得的結果筆數很少, 全部組好再切
  def paginate_rows(rows)
    @counts = TYPES.index_with { |t| rows.count { it[:type] == t } }
    rows = rows.select { @types.include?(it[:type]) }
    @num_found = rows.size
    rows = rows.drop(@start)
    @rows.nil? ? rows : rows.first(@rows)
  end

  # 關鍵詞查詢: 先數各類筆數, 再只對落在 start ~ start + rows 範圍內的部分
  # 下 OFFSET / LIMIT 組資料。每筆都要附佛典資訊, 全部組完再切就省不到時間。
  def paginate_scopes(scopes)
    @counts = scopes.transform_values(&:count)
    @num_found = @types.sum { @counts[it] }

    result = []
    offset = @start
    remaining = @rows
    @types.each do |type|
      break if remaining == 0

      count = @counts[type]
      if offset >= count
        offset -= count
        next
      end

      relation = scopes[type].offset(offset)
      unless remaining.nil?
        take = [ remaining, count - offset ].min
        relation = relation.limit(take)
        remaining -= take
      end
      result.concat(send("find_#{type}", relation))
      offset = 0
    end
    result
  end

  # q 裡的 % _ 要當一般字元比對, 否則 q=% 等於 LIKE '%%%' 全表掃描 (見 index 的說明)。
  # 搭配的 SQL 要寫 ESCAPE '\': SQLite (測試環境) 的 LIKE 預設沒有 escape 字元。
  def like_pattern(q)
    "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
  end

  def catalog_scope(q)
    # 沒有 ORDER BY 時 PostgreSQL 不保證順序; id 是匯入時的目錄順序
    CatalogEntry.where("(label NOT LIKE '%=%') AND (label LIKE ? ESCAPE '\\')", like_pattern(q)).order(:id)
  end

  def work_scope(q)
    Work.where.not(juan_list: nil) # CBETA 未收錄的不要
        .where("title LIKE ? ESCAPE '\\'", like_pattern(q)).order(:sort_order, :id)
  end

  def toc_scope(q)
    # 同一部佛典的節點 sort_order 相同, 只排 sort_order 時每次查詢的順序都可能不同;
    # id 是匯入時的文件順序
    # 佛典不在 works 表的節點不回傳 (find_toc 會略過), 先排除才不會算進筆數
    TocNode.where("label LIKE ? ESCAPE '\\'", like_pattern(q)).where(work: Work.select(:n)).order(:sort_order, :id)
  end

  def find_catalog(entries)
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
  
  def find_toc(toc_nodes)
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
  
  def find_work(works)
    r = []
    works.includes(:places).each do |w|
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
      return paginate_rows([]) if ce.nil?

      # 呼叫端 (index) 看到 performed? 就不再 render
      redirect_to controller: 'catalog_entry', action: 'index', q: ce.n
      return
    elsif q.match(/^(#{CBETA::CANON})\d{2,3}n(\w{4,5})$/) # ex: T01n0001
      q = $1 + $2
      w = Work.find_by n: q
      return paginate_rows([]) if w.nil?

      row = { type: 'work' }
      row.merge! w.to_hash
      result = paginate_rows([ row ])
    elsif q.match(CBETA::WORK_ID) # ex: T0001, JB271, ZWa073
      works = Work.where("n LIKE ?", "#{q}%")
      result = []
      works.each do |w|
        row = { type: 'work' }
        row.merge! w.to_hash
        result << row
      end
      result = paginate_rows(result)
    else
      result = paginate_scopes(
        'catalog' => catalog_scope(q),
        'work' => work_scope(q),
        'toc' => toc_scope(q)
      )
    end
    result
  end

end
