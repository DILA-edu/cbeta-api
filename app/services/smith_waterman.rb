# https://gist.github.com/vincentchu/1041980
class SmithWaterman
  attr_reader :str_a, :str_b, :str_a_arr, :str_b_arr, :m, :n, :config, :score

  # 分數上界: gain × 兩字串共同字元數 (multiset 交集)。
  #
  # 最佳路徑的分數 = Σ(match gain) + Σ(mismatch／gap penalty)，而 penalty <= 0，
  # 因此分數不可能超過「全部共同字元都對齊上」的情形。成本是 O(m+n)，
  # 用來在建矩陣 (O(m×n)) 之前先剔除不可能達到門檻的候選。
  #
  # 字元單位與 assign_cell 的比較一致，都用 unpack('U*') 的 codepoint。
  def self.max_score(str_a, str_b, gain: 2)
    counts = str_a.unpack('U*').tally
    common = 0
    str_b.unpack('U*').each do |c|
      n = counts[c]
      next if n.nil? || n.zero?

      counts[c] = n - 1
      common += 1
    end
    gain * common
  end

  def initialize(stra, strb, opts = {})
    @str_a  = stra
    @str_b  = strb

    @str_a_arr = stra.unpack("U*")
    @str_b_arr = strb.unpack("U*")

    @m      = str_a.length + 1
    @n      = str_b.length + 1
    # m×n 的矩陣攤平成一維 Array，索引 i*n+j。
    # 原本是 Matrix 類別，每個 cell 存取都要經過一次帶 bounds check 的 method call，
    # 而 similar 一次查詢要算兩千筆候選 × 上千個 cell。
    @mat    = Array.new(@m * @n, 0)

    @config = opts.with_defaults(gain: 2, penalty: -1)
    raise 'SmithWaterman penalty 必須 <= 0' if @config[:penalty] > 0

    @score_insert = @config[:penalty]
    @score_delete = @config[:penalty]
    @score_miss   = @config[:penalty]
    @score_match  = @config[:gain]
  end

  # 只算分數，不做 traceback。
  # 分數不到門檻的候選會被直接丟棄，traceback 對它們是白做的。
  def score!
    iterate_over_cells! if @score.nil?
    @score
  end

  def align!
    score!
    alignment
  end

  # traceback 延後到真正要用 alignment 時才做 (alignment_inspect / _b)。
  def alignment
    return @alignment unless @alignment.nil?

    score!
    find_optimal_path
    @alignment
  end

  def alignment_inspect
    
    la = "... "
    lb = "... "
    
    alignment.each_with_index do |pos, i|
      next if (i == 0)
      
      case alignment[i-1][2]
        when :down
          la += [ str_a_arr[pos[0]-1] ].pack("U*")
          lb += "-"
        when :right
          la += "-"
          lb += [ str_b_arr[pos[1]-1] ].pack("U*")
        else
          la += [ str_a_arr[pos[0]-1] ].pack("U*")
          lb += [ str_b_arr[pos[1]-1] ].pack("U*")
      end
    end
    
    "#{la} ...\n#{lb} ..."    
  end
  
  def alignment_inspect_b
    r = ""
    x = 0
    
    alignment.each_with_index do |pos, i|
      if (i == 0)
        r << paint_char_in_a(@str_b[0...pos[1]])
        next
      end
      x = pos[1]
      char = @str_b[x-1]
      case alignment[i-1][2]
      when :down
      when :right
        if pos[0] == @str_a.size
          r << char
        else
          r << "<del>#{char}</del>"
        end
      else
        if @str_a[pos[0]-1] == char
          r << "<mark>#{char}</mark>"
        else
          r << "<mark><del>#{char}</del></mark>"
        end
      end
    end

    if x < @str_b.size
      r << paint_char_in_a(@str_b[x..-1])
    end
    
    r.gsub!('</mark><mark>', '')
    r
  end

  private
  
  def find_optimal_path    
    @alignment = []    
    recurse_optimal_path(@i_max, @j_max)

    @alignment.reverse!
    @alignment.each_with_index do |pos, i|
      next_pos = alignment[i+1]
      next if next_pos.nil?

      del_i = next_pos[0] - pos[0]
      del_j = next_pos[1] - pos[1]
      direction = case (del_i + del_j)
        when 2 then  :diagonal
        when 1
          (del_i > del_j) ? :down : :right
      end

      pos << direction
    end
  end

  def recurse_optimal_path(i_curr, j_curr)    
    @alignment << [i_curr, j_curr]
    
    row  = i_curr * @n
    prev = row - @n

    values = [
      @mat[prev + j_curr - 1],
      @mat[prev + j_curr],
      @mat[row + j_curr - 1]
    ]

    ii, jj = case values.index(values.max)
      when 0 then [i_curr-1, j_curr-1]
      when 1 then [i_curr-1, j_curr]
      when 2 then [i_curr  , j_curr-1]
    end

    if (@mat[row + j_curr] == 0)
      return
    else
      return recurse_optimal_path(ii, jj)
    end
  end
  
  def iterate_over_cells!
    
    @score = -1
    @i_max = 0
    @j_max = 0
    
    (2..m).each do |i|
      (2..n).each do |j|
        assign_cell(i-1, j-1)
      end
    end
  end
  
  def assign_cell(i, j)
    score = (@str_a_arr[i-1] == @str_b_arr[j-1]) ? @score_match : @score_miss

    row  = i * @n
    prev = row - @n

    value = @mat[prev + j - 1] + score
    v = @mat[prev + j] + @score_delete
    value = v if v > value
    v = @mat[row + j - 1] + @score_insert
    value = v if v > value
    value = 0 if value < 0

    if (value >= @score)
      @score = value
      @i_max = i
      @j_max = j
    end

    @mat[row + j] = value
  end

  def paint_char_in_a(s)
    r = ''
    s.chars.each do |c|
      if @str_a.include?(c)
        r << "<em>#{c}</em>"
      else
        r << c
      end
    end
    r
  end
end
