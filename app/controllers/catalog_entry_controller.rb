class CatalogEntryController < ApplicationController
  include ApiKeyAuthentication

  def index
    with_release_etag { render_index }
  end

  private

  def render_index
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

  def get_entries_by_parent(parent)
    results = []
    CatalogEntry.where(parent: parent).order(:sort).each do |ce|
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
    catalog_entry = CatalogEntry.find_by_vol(vol) # ex: T01
    return [] if catalog_entry.nil?

    get_entries_by_parent(catalog_entry.n)
  end
  
  def get_label_by_entry(id)
    entry = CatalogEntry.find_by(n: id)
    return nil if entry.nil?
    entry.label
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
  
end
