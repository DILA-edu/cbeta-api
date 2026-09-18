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
    entries = CatalogEntry.where("(label NOT LIKE '%=%') AND (label LIKE ?)", "%#{q}%")
    r = []
    entries.each do |e|
      row = { type: 'catalog', n: e.n, label: e.label }
      unless e.work.nil?
        work_info = Work.get_info_by_id(e.work)
        row.merge! work_info
      end
      r << row
    end
    r
  end
  
  def find_toc(q)
    toc_nodes = TocNode.where("label LIKE ?", "%#{q}%").order(:sort_order)
    r = []
    toc_nodes.each do |t|
      row = { type: 'toc', label: t.label, label_path: t.label_path, work: t.work, lb: t.lb }
      w = Work.get_info_by_id(t.work)
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
    works = works.where("title LIKE ?", "%#{q}%").order(:sort_order)
    r = []
    works.each do |w|
      row = { type: 'work' }
      row.merge! w.to_hash
      r << row
    end
    r
  end
  
  def search_by_query_term
    q = params[:q]
    if q.match(/^(#{CBETA::CANON})\d{2,3}$/) # ex: T01
      canon = $1
      parent = "Vol-#{canon}"
      ce = CatalogEntry.where("(parent=?) AND (label LIKE ?)", parent, "#{q}%").first
      redirect_to controller: 'catalog_entry', action: 'index', q: ce.n
    elsif q.match(/^(#{CBETA::CANON})\d{2,3}n(\w{4,5})$/) # ex: T01n0001
      q = $1 + $2
      w = Work.find_by n: q
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
