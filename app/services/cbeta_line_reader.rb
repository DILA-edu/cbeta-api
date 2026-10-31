# 讀取 CBETA P5a XML,回傳 { lb => 該行原始文字 }。
#
# 「原始文字」指:缺字(<g>)已展開為顯示字元、<note> 依規則納入或略過、
# 多餘換行已移除,但「標點/空格尚未剝除」。是否剝除、哪些字元佔字位,
# 一律交由呼叫端以 CbetaString 決定,避免字位規則散落多處。
#
# 這段邏輯原本內嵌於 import:layers,抽成 service 後由 runtime 與
# migration 共用,確保兩邊建行方式完全一致。
class CbetaLineReader
  # @param gaijis [Hash] MyCbetaShare.get_cbeta_gaiji 的結果
  def initialize(gaijis)
    @gaijis = gaijis
  end

  # @param xml_path [String] XML 檔完整路徑
  # @return [Hash{String=>String}] lb => 原始行文字
  def read(xml_path)
    @lines = {}
    @lb = nil
    # 例: X01n0001.xml → X
    @canon = CBETA.get_canon_from_vol(File.basename(xml_path).split('n').first)
    doc = File.open(xml_path) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    traverse(doc.root)
    @lines
  end

  private

  def e_g(e)
    id = e['ref'].sub(/^#/, '')
    r = '●'
    if @gaijis.key? id
      g = @gaijis[id]
      if g.key? 'uni_char'
        r = g['uni_char']
      elsif g.key? 'norm_uni_char'
        r = g['norm_uni_char']
      elsif g.key? 'norm_big5_char'
        r = g['norm_big5_char']
      end
    end
    @lines[@lb] << r unless @lb.nil?
  end

  # 只取本藏的行: 卍續藏 XML 夾著新文豐版的 <lb ed="R150">, 當成新的一行
  # 會把文字記到不存在的行號下, 頁碼重複時還會清掉已讀到的行
  # (同 x2h_for_ui、notes.rake 的 e_lb)
  def e_lb(e)
    return if e['type'] == 'old'
    return if e['ed'] && e['ed'] != @canon

    @lb = e['n']
    @lines[@lb] = +''
  end

  def e_note(e)
    return if e['type'] == 'add'
    return if e['type'] == 'orig'
    return if e.key?('type') and e['type'].match(/^cf\d+$/)
    traverse(e)
  end

  def handle_node(e)
    return '' if e.comment?
    return handle_text(e) if e.text?
    case e.name
    when 'mulu', 'rdg'
      # 目次標記與異文不取文字
    when 'g'    then e_g(e)
    when 'lb'   then e_lb(e)
    when 'note' then e_note(e)
    else traverse(e)
    end
  end

  def handle_text(e)
    return if @lb.nil?
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # 只移除多餘換行,標點/空格保留(與 cbeta gem 產生 HTML 時一致)
    s = s.gsub(/[\n\r]/, '')
    @lines[@lb] << s
  end

  def traverse(e)
    e.children.each { |c| handle_node(c) }
  end
end
