require 'json'

class ImportCross
  def initialize
    @data_folder = Rails.application.config.cbeta_data
    @xml_root = Rails.application.config.cbeta_xml
  end
  
  def import
    # import:work_info 也會新增 XmlFile
    # 所以這裡不能清 XmlFile
    # XmlFile.delete_all

    import_from_cross_vols
  end
  
  private
  
  def get_info_from_xml(xml_file, data)
    $stderr.puts "import_cross #{xml_file}"
    doc = File.open(xml_file) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    juans = doc.xpath("//milestone[@unit='juan']")
    data[:juans] = juans.size
    data[:juan_start] = juans.first['n'].to_i
  end
  
  def import_from_cross_vols
    fn = File.join(@data_folder, 'special-works', 'work-cross-vol.json')
    $stderr.puts "import_cross #{fn}"
    works = File.open(fn) { |f| JSON.load(f) }
    
    works.each_pair do |k,v|
      if v.is_a?(Hash)
        update_title(k, v['title'])
        files = v['files']
      else
        files = v
      end
      
      canon = CBETA.get_canon_id_from_work_id(k)
      data = { work: k }
      files.each do |f|
        data[:file] = f
        data[:vol] = f.sub(/^([A-Z]{1,2}\d+)n.*$/, '\1')
        xml_fn = File.join(@xml_root, canon, data[:vol], f+'.xml')
        get_info_from_xml(xml_fn, data)
        XmlFile.create data
      end
    end
  end
  
  def update_title(work_n, title)
    w = Work.find_by n: work_n
    w.title = title
    w.save
  end
  
end