class CheckMetadata

  def initialize
    @metadata = Rails.configuration.cbeta_data
  end
  
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
    unless errors.empty?
      puts "以下典籍缺 title:"
      puts errors.join(', ')
    end
    errors.empty?
  end
  
  private

  def read_titles
    fn = File.join(@metadata, 'titles/all-title-byline.csv')
    r = {}
    CSV.foreach(fn, headers: true) do |row|
      id = row['典籍編號']
      r[id] = row['典籍名稱']
    end
    r
  end

end