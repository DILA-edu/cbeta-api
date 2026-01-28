class CheckStat
  def initialize
    @base = Rails.root.join('public', 'download', 'stat')
    read_cats
    read_vols
    read_works
  end

  def check
    check_cats
    check_T0220
  end

  private

  def check_cats
    cats2 = Hash.new(0)
    @works.each_value do |w|
      next if w[:cats].nil?
      w[:cats].split(',') do |cat|
        cats2[cat] += w[:cjk_chars]
      end
    end

    @cats.each do |k, v1|
      v2 = cats2[k]
      unless v1 == v2
        abort <<~TXT
          [#{__LINE__}] 部類字數不符: #{k}
          根據部類字數統計: #{v1}
          根據分部字數統計: #{v2}
          差距: #{(v1-v2).abs}
        TXT
      end
    end
  end

  def check_T0220
    i1 = @works['T0220'][:cjk_chars]
    i2 = %w[T05 T06 T07].sum { @vols[it] }
    abort "[#{__LINE__}] T0220 字數不符" unless i1 == i2
  end

  def read_cats
    @cats = {}
    path = File.join(@base, 'cbeta-word-count-cat.csv')
    puts "read #{path}"
    CSV.foreach(path, headers: true) do |row|
      k = row['category']
      @cats[k] = row['cjk_chars'].to_i
    end
  end

  def read_vols
    @vols = {}
    path = File.join(@base, 'cbeta-word-count-vol.csv')
    puts "read #{path}"
    CSV.foreach(path, headers: true) do |row|
      k = row['vol']
      @vols[k] = row['cjk_chars'].to_i
    end
  end

  def read_works
    @works = {}
    path = File.join(@base, 'cbeta-word-count.csv')
    puts "read #{path}"
    CSV.foreach(path, headers: true) do |row|
      k = row['work']
      @works[k] = { 
        cjk_chars: row['cjk_chars'].to_i,
        cats: row['category']
      }
    end
  end
end
