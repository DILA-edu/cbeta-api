class ChangeLogFont

  def initialize(config)
    @config = config
    @base = config[:change_log]
  end

  def run
    v = @config[:q2]
    handle_file("#{v}.htm")
    handle_file("#{v}-text.htm")
    handle_file("#{v}-punc.htm")
  end

  private

  def handle_file(f)
    fn = File.join(@base, f)
    html = File.read(fn)
    # Ext E, F 必須個別指定定型才能正確顯示 (2020-12-08 測試結果)
    # U+2B820..U+2CEA1, CJK Unified Ideographs Extension E, Unicode 8.0
    # U+2CEB0..U+2EBE0, CJK Unified Ideographs Extension F, Unicode 10.0
    html.gsub!(/[𫠠-𬺡𬺰-𮯠]/) do
      "<span class='hmc'>#{$&}</span>"
    end

    # 如果使用 ins, del 標記，在 ms word 開啟會出現「追蹤修訂」左邊線
    html.gsub!(/<ins>/, '<span class="ins">')
    html.gsub!(/<\/ins>/, '</span>')
    html.gsub!(/<del>/, '<span class="del">')
    html.gsub!(/<\/del>/, '</span>')
    File.write(fn, html)
  end

end