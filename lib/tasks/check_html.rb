class CheckHTML
  def initialize
    @base = Rails.root.join('data', 'html')
  end

  def check
    check_T54n2133Ap1191a16
  end
  
  private
  
  def check_T54n2133Ap1191a16
    fn = File.join(@base, 'T', 'T2133A', '001.html')
    html = File.read(fn)
    regex = /講.*?道.*?論.*?妙/m
    if html =~ regex
      if $&.include?('</p>')
        abort "#{__LINE__} '講道論妙 應該要在同一段落。"
      end
    else
      abort "#{__LINE__} HTML 應 match #{regex.source}"
    end
  end
end
