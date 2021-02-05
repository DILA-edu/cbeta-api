class CatalogEntryController < ApplicationController
  def index
    if params[:vol]
      results = get_entries_by_vol(params[:vol])
      label = params[:vol]
    elsif params[:q]
      results = get_entries_by_parent(params[:q])
      label = get_label_by_entry(params[:q])
    else
      results = get_entries_by_parent('root')
      label = 'CBETA 漢文佛典集成'
    end

    r = {
      num_found: results.size,
      label: label,
      results: results
    }
    my_render(r)
  end
  
  private
  
  def get_entries_by_parent(parent)
    results = []
    CatalogEntry.where(parent: parent).order(:n).each do |ce|
      d = { n: ce.n }
      target = nil
      if ce.node_type == 'work'
        target = get_info_from_work_node(ce, d)
      else
        d[:label] = ce.label 
      end
      unless ce.juan_start.nil?
        d[:juan_start] = ce.juan_start
        d[:juan_end] = ce.juan_end
      end
      if ce.file.nil?
        unless target.nil?
          vol = target.vol
          vol = vol.split('..')[0] if vol.include? '..'
          d[:file] = CBETA.get_xml_file_from_vol_and_work(vol, target.n)
        end
      else
        d[:file] = ce.file
      end
      d[:lb] = ce.lb unless ce.lb.nil?
      d[:node_type] = ce.node_type
      results << d
    end
    results
  end
  
  def get_entries_by_vol(vol)
    if vol.match(/^(#{CBETA::CANON})\d{2,3}$/) # ex: T01
      canon = $1
      parent = "Vol-#{canon}"
      catalog_entry = CatalogEntry.where("(parent=?) AND (label LIKE ?)", parent, "#{vol}%").first
      get_entries_by_parent(catalog_entry.n)
    else
      []
    end
  end
  
  def get_label_by_entry(id)
    entry = CatalogEntry.find_by(n: id)
    return nil if entry.nil?
    entry.label
  end

  def handle_alt(alt)
    if alt.size <= 6
      r = Work.get_info_by_id(alt)
    else
      # 格式是 cbeta 行首資訊
      if alt.match(/^([A-Z])\d{2,3}n(\w{5})p(\d{4}[a-z]\d\d)$/)
        work_id = $1 + $2
        lb = $3
        work_id.sub!(/^(.*?)_$/, '\1')
        r = Work.get_info_by_id(work_id)
        r[:lb] = lb
      else
        abort "#{__LINE__} alt format error: #{alt}"
      end
    end
    r
  end
  
  def handle_alts(alt)
    r = []
    alts = alt.split('+')
    alts.each do |a|
      r << handle_alt(a)
    end
    r
  end

  def logical_work(node)
    w = Work.find_by n: node.work
    if w.alt.nil?
      r = physical_work(node, w)
      r = [r]
    else
      r = handle_alts(w.alt)
    end
    r
  end
  
  def non_work_node(node)
    r = { 
      n: node.n,
      label: node.label 
    }
    unless node.juan_start.nil?
      r[:juan_start] = ce.juan_start
      r[:juan_end] = ce.juan_end
    end
    r
  end
  
  # ce: catalog entry
  def get_info_from_work_node(ce, data)
    data[:work] = ce.work
    work = Work.find_by n: ce.work
    return nil if work.nil?
    
    if ce.juan_start.nil?
      juan = "#{work.juan}卷"
      data[:juan_start] = work.juan_start unless work.juan_start.nil?
    else
      juan = "#{ce.juan_start}~#{ce.juan_end}卷"
    end
    
    if ce.label.nil?
      data[:label] = data[:work]
      title = work.title
      if ce.work.start_with? 'Y'
        data[:label] += " #{title}"
      else
        data[:label] += " #{title} (#{juan})"
      end
    else
      data[:label] = ce.label
    end
    
    data[:category] = work.category
    data[:creators] = work.creators unless work.creators.nil?
    work
  end
  
  def physical_work(ce_node, work_node)
    data = { 
      work: work_node.n,
      label: work_node.n
    }
    if ce_node.file.nil?
      data[:file] = work_node.vol + 'n' + work_node.n[1..-1]
    else
      data[:file] = ce_node.file
    end
    if ce_node.juan_start.nil?
      juan = "#{work_node.juan}卷"
    else
      juan = "#{ce_node.juan_start}~#{ce_node.juan_end}卷"
    end
    data[:label] += " #{work_node.title} (#{juan})"
    data
  end
end
