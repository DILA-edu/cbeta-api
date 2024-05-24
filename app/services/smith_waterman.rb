# https://gist.github.com/vincentchu/1041980
require_relative 'matrix'

class SmithWaterman
  attr_reader :str_a, :str_b, :str_a_arr, :str_b_arr, :m, :n, :mat, :config, :alignment, :score

  def initialize(stra, strb, opts = {})
    @str_a  = stra
    @str_b  = strb
    
    @str_a_arr = stra.unpack("U*")
    @str_b_arr = strb.unpack("U*")
    
    @m      = str_a.length + 1
    @n      = str_b.length + 1
    @mat    = Matrix.new(m, n)
    
    @config = opts.with_defaults(gain: 2, penalty: -1)
    raise 'SmithWaterman penalty 必須 <= 0' if @config[:penalty] > 0

    @score_insert = @config[:penalty]
    @score_delete = @config[:penalty]
    @score_miss   = @config[:penalty]
    @score_match  = @config[:gain]
  end

  def align!
    iterate_over_cells!
    find_optimal_path
    
    return alignment
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
    
    values = [
      mat[i_curr-1, j_curr-1],
      mat[i_curr-1, j_curr],
      mat[i_curr  , j_curr-1]
    ]
    
    ii, jj = case values.index(values.max)
      when 0 then [i_curr-1, j_curr-1]
      when 1 then [i_curr-1, j_curr]
      when 2 then [i_curr  , j_curr-1]
    end    
    
    if (mat[i_curr, j_curr] == 0)
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
    score = (str_a_arr[i-1] == str_b_arr[j-1]) ? @score_match : @score_miss

    value = [
      0,
      mat[i-1, j-1] + score,
      mat[i-1, j] + @score_delete,
      mat[i, j-1] + @score_insert
    ].max
    
    if (value >= @score)
      @score = value
      @i_max = i
      @j_max = j
    end
    
    mat[i,j] = value
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
