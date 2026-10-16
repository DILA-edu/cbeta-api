module TocNodeHelper
  def get_toc_by_work_id(w)
    fn = toc_path(w)
    return nil unless File.exist? fn
    
    s = File.read(fn)
    JSON.parse(s)
  end

  def toc_path(w)
    Rails.root.join('data', 'toc', CBETA.get_canon_id_from_work_id(w), "#{w}.json")
  end
end
