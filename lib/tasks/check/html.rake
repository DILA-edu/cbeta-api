namespace :check do  
  desc "檢查 HTML for UI"
  task :html => :environment do
    CheckHTML.new.check
  end
end

class CheckHTML
  def initialize
    @base = Rails.root.join('data', 'html')
  end

  def check
    check_T18n0859_p0178a18
    check_T18n0860_p0182c10
    check_T54n2133Ap1191a16
  end
  
  private

  def check_T18n0859_p0178a18
    fn = File.join(@base, 'T', 'T0859', '001.html')
    html = File.read(fn)
    regex = /0178a18.*南.*0178a19/m

    unless html =~ regex
      raise "HTML 應 match #{regex.source}\n  fn: #{fn}".red
    end
  end

  def check_T18n0860_p0182c10
    fn = File.join(@base, 'T', 'T0860', '001.html')
    html = File.read(fn)
    regex = /0182c10.*帝.*0182c11/m

    unless html =~ regex
      raise "HTML 應 match #{regex.source}\n  fn: #{fn}".red
    end
  end

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
