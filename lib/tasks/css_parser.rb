class CSSParser
  def initialize(str)
    a = str.split(';')
    @hash = {}
    a.each do |s|
      k, v = s.split(':')
      @hash[k.strip] = v.strip
    end
  end

  def ==(other)
    @hash == other.hash
  end

  def to_class
    if @hash.keys.size == 1
      case @hash.keys.first
      when "margin-left"
        i = @hash["margin-left"].delete_suffix("em").to_i
        "m#{i}"
      when "text-indent"
        i = @hash["text-indent"].delete_suffix("em").to_i
        if i >= 0
          "i#{i}"
        else
          "j#{-i}"
        end
      end
    elsif @hash.keys.size == 2 and @hash.key?("margin-left") and @hash.key?("text-indent")
      m = @hash["margin-left"].delete_suffix("em").to_i
      i = @hash["text-indent"].delete_suffix("em").to_i
      if i >= 0
        "m#{m}_i#{i}"
      else
        "m#{m}_j#{-i}"
      end
    end
  end
end
