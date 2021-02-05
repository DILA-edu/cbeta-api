class ImportSynonym
  def initialize
    @folder = Rails.root.join('data-static')
  end
  
  def import
    $stderr.puts "清除舊資料"
    Term.delete_all

    $stderr.puts "匯入新資料"

    read_synonyms
    arrange_synonyms
    @inserts = []
    @synonyms.each_pair do |term, synonyms|
      s = synonyms.to_a.join("\t")
      @inserts << "('#{term}', '#{s}')"
    end

    $stderr.puts "execute SQL insert #{number_to_human(@inserts.size)} records"
    sql = 'INSERT INTO terms '
    sql += '("term", "synonyms")'
    sql += ' VALUES ' + @inserts.join(", ")
    $stderr.puts Benchmark.measure {
      ActiveRecord::Base.connection.execute(sql) 
    }
  end

  private

  def arrange_synonyms
    @synonyms = {}
    @groups.each_pair do |gid, terms|
      term = terms.first
      terms[1..-1].each do |t|
        book_synonym(term, t)
        book_synonym(t, term)
      end
    end
  end

  def book_synonym(t1, t2)
    @synonyms[t1] = Set.new unless @synonyms.key?(t1)
    @synonyms[t1] << t2
  end

  def read_synonyms
    fn = File.join(@folder, 'synonym.txt')
    @groups = {}
    IO.foreach(fn) do |line|
      next if line.empty?
      line.chomp!
      a = line.split(',')
      gid = a[0].to_i
      @groups[gid] = [] unless @groups.key?(gid)
      @groups[gid] << a[1]
    end
  end
  
end