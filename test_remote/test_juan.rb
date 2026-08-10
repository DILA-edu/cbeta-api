# frozen_string_literal: true

require 'nokogiri'

class JuanTest < Minitest::Test
  def setup
    @url = "juans"
  end
  
  def test_cn
    save_referer = $referer
    $referer = 'https://cbetaonline.cn/'

    r = get_json(@url, work: "YP0021", juan: 1)
    refute_equal(r['num_found'], 0)

    $referer = save_referer
  end

  def test_facs_k
    html = get_html(work: 'T0001', juan: 1)
    doc = Nokogiri::HTML(html)
    # <a class="facsimile" data-canon="K" data-s="dongguk" data-ref="K0647.17.0815.a">
    node = doc.at_xpath("//a[@data-canon='K']")
    refute_nil(node, 'T0001_001 (高麗藏掃描圖 連結) 不存在')
  end
  
  def test_get_juan
    juans = [
      { work: 'A1561', juan: 7 },
      { work: 'Y0030', juan: 3 }
    ]
    juans.each do |params|
      r = get_json(@url, params)
      refute_equal(r['num_found'], 0)
    end
  end

  def test_note_add
    html = get_html(work: 'T0278', juan: 55)
    assert_same(2, html.scan(/cb_note_3/).size, "CBETA note id 數量不正確。")
  end

  def test_note_authorial
    html = get_html(work: 'Y0034', juan: 3)
    assert_includes(html , '《俱舍論（光）記》', '<note type="authorial"> 未正確呈現')
  end

  # <note subtype="jie">
  def test_jie  
    html = get_html(work: 'X0252', juan: 1)
    regexp = /<a class='noteAnchor' href='#n0180j01' data-label='解01'>/
    assert_match(regexp, html, 'noteAnchor「解」label 有誤。')
  end

  # <ref cRef="PTS.Vin.3.1"/>
  def test_pts
    html = get_html(work: 'N0001', juan: 1)
    regexp = /<span class="hint"[^>]* data-text="PTS.Vin.3.1"[^>]*>/
    assert_match(regexp, html, "PTS ref 標記有誤。")
  end

  # <tt rend="inline">
  def test_inline
    html = get_html(work: 'T0939', juan: 1)
    regexp = /<span[^>]* code='SD-E17C'[^>]*>(<[^>]*>)*吽/
    assert_match(regexp, html, "tt inline")
    
    html = get_html(work: 'T0220', juan: 600)
    regexp = /<span[^>]* code='SD-A557'[^>]*\/>(<[^>]*>)*怛/
    assert_match(regexp, html, "tt inline")
  end

  def test_key
    html = get_html(work: 'T0001', juan: 1)
    doc = Nokogiri::HTML(html)
    node = doc.at_xpath("//a[@href='#cb_note_1']")
    assert node.key?('data-key'), "連結 校訂考證資料庫"
  end
  
  def test_place
    html = get_html(work: 'GA0008', juan: 1)
    assert_includes(html, 'place', 'GA0008卷1應含地名')
  end

end
