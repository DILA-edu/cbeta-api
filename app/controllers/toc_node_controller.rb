class TocNodeController < ApplicationController  
  include TocNodeHelper

  def index
    start = Time.now
    if params.key? :work
      toc = get_toc_by_work_id(params[:work])
      result = toc.nil? ? [] : [toc]
    else
      result = search_by_query_term
    end

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
        logger.fatal "Error get_info_by_id(#{t.work})"
        abort
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
    elsif q.match(/^#{CBETA::CANON}[AB\d]\d{3}[a-zA-Z]?$/) # ex: T0001, JB271
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
