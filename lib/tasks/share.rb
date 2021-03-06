class MyCbetaShare
  def self.get_cbeta_gaiji
    folder = Rails.application.config.cbeta_gaiji
    fn = File.join(folder, 'cbeta_gaiji.json')
    s = File.read(fn)
    JSON.parse(s)
  end
  
  def self.get_cbeta_gaiji_skt
    folder = Rails.application.config.cbeta_gaiji
    fn = File.join(folder, 'cbeta_sanskrit.json')
    s = File.read(fn)
    JSON.parse(s)
  end
  
  def self.get_update_date(xml_fn)
    folder = File.dirname(xml_fn)
    basename = File.basename(xml_fn)
    r = nil
    Dir.chdir(folder) do
      s = `git log -1 --pretty=format:"%ai" #{basename}`
      r = s.sub(/^(\d{4}\-\d\d\-\d\d).*$/, '\1')
    end
    r
  end
  
  def self.get_work_categories
    fn = File.join(Rails.application.config.cbeta_data, 'category', 'work_categories.json')
    s = File.read(fn)
    works = JSON.parse(s)
    r = {}
    works.each_pair do |k,v|
      r[k] = v['category_names']
    end
    r
  end
  
  def self.remove_puncs(s)
    return '' if s.empty?
    r = /[#{Regexp.escape(CBETA::PUNCS)}]/
    s.gsub(r, '')
  end
  
end