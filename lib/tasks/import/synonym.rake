namespace :import do    
  desc "匯入 同義詞"
  task :synonym => :environment do
    ImportSynonym.new.import
  end
end

class ImportSynonym
  def initialize
    @folder = File.join(Rails.configuration.cb.git, 'synonyms')
    @xml_path = File.join(@folder, 'synonyms.xml')

    Dir.chdir(@folder) do
      puts '-' * 10
      puts "git pull in #{@folder}"
      system('git pull')
      puts '-' * 10
    end
  end
  
  def import
    @log = File.open(Rails.root.join('log', 'import-synonym.log'), 'w')
    validate

    $stderr.puts "清除舊資料"
    Term.delete_all

    $stderr.puts "匯入新資料"

    read_synonyms
    arrange_synonyms
    moe_variant_words # 教育部 異形詞

    inserts = []
    @synonyms.each_pair do |term, synonyms|
      s = synonyms.to_a.join("\t")
      @log.puts "#{__LINE__} #{term} => #{s}"
      inserts << { term:, synonyms: s }
    end

    Term.insert_all(inserts)
    puts "Term records: #{number_with_delimiter(Term.count)}"
  end

  private

  def arrange_synonyms
    @synonyms = {}
    @groups.each_pair do |gid, terms|
      book_synonym_array(terms)
    end
  end

  def book_synonym(t1, t2)
    @log.puts "book_synonym, t1: #{t1}, t2: #{t2}"
    @synonyms[t1] = Set.new unless @synonyms.key?(t1)
    @synonyms[t1] << t2
  end
  
  # 兩兩之間 建立 近義詞 關係
  def book_synonym_array(terms)
    terms.permutation(2) do |t1, t2|
      book_synonym(t1, t2)
    end
  end

  # 匯入 教育部 異形詞
  def moe_variant_words
    fn = Rails.root.join('data', 'moe-variant-words.csv')
    CSV.foreach(fn, headers: true) do |row|
      a = row['詞組'].split('／')
      book_synonym_array(a)
    end
  end

  def read_synonyms
    puts "read #{@xml_path}"
    doc = File.open(@xml_path) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!

    doc.xpath('//def').remove
    doc.xpath('//note').remove
    doc.xpath('//orig').remove

    @groups = {}
    doc.root.xpath('sense').each do |sense|
      id = sense['id']
      terms = sense.xpath('form').to_a.map { it.text }
      @groups[id] = terms
      @log.puts "#{__LINE__} group id: #{id}, terms: #{terms.inspect}"
    end
  end

  def validate
    xml = Nokogiri::XML(File.read(@xml_path))

    fn = File.join(@folder, 'synonyms.rng')
    rng = Nokogiri::XML::RelaxNG(File.read(fn))

    errors = rng.validate(xml)

    if errors.empty?
      puts "xml file is valid.".green
    else
      raise 'synonyms.xml not valid'.red
    end
  end
end
