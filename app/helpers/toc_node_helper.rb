module TocNodeHelper
  def get_toc_by_work_id(w)
    canon = CBETA.get_canon_id_from_work_id(w)
    fn = Rails.root.join('data', 'toc', canon, w+'.json')
    return nil unless File.exist? fn
    
    s = File.read(fn)
    JSON.parse(s)
  end  
end
