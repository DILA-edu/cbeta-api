# https://gist.github.com/vincentchu/1041980
class Matrix
  
  IndexOverflow = Class.new(StandardError)
  
  attr_reader :dims, :nrows, :ncols
  
  def initialize(mm, nn)
    @dims  = [mm, nn]
    @nrows = mm
    @ncols = nn
    @m     = Array.new(mm)

    (1..mm).each {|i| @m[i-1] = Array.new(nn, 0)}
  end
  
  def inspect
    @m.inject("") do |str, row|
      str +=  row.collect {|v| sprintf("%5d", v)}.join(" ") + "\n"
    end
  end  

  def [](i, j)    
    raise IndexOverflow if ((i >= nrows) || (j >= ncols))
    
    @m[i][j]
  end
  
  def []=(i, j, k)
    raise IndexOverflow if ((i >= nrows) || (j >= ncols))

    @m[i][j] = k
  end
end
