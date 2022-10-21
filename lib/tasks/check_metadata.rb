class CheckMetadata
  def check
    $stderr.puts "check metadata"
    @titles = read_titles
    src = Rails.configuration.cbeta_xml
    errors = []
    Dir["#{src}/**/*.xml"].sort.each do |fn|
      bn = File.basename(fn, '.*')
      id = CBETA.get_work_id_from_file_basename(bn)
      unless @titles.key? id
        errors << bn
      end
    end
    if errors.empty?
      puts "檢查通過，未發現錯誤。".green
    else
      puts "以下佛典缺 title:".red
      puts errors.join(', ')
    end
    errors.empty?
  end
  
  private

  def read_titles
    src = Rails.configuration.x.work_info
    r = {}
    Dir.glob("#{src}/*.json") do |f|
      works = JSON.load_file(f)
      works.each do |id, h|
        r[id] = h['title']
      end
    end
    r
  end

end
