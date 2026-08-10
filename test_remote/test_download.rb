class DownloadTest < Minitest::Test
  def test_all_creators
    url = 'download/all-creators.json'
    r = get_json(url)
    assert_operator(r.size, :>=, 2182)    
  end

  def test_creator_strokes_works
    url = "download/scope-selector/creators-by-strokes-with-works.json"
    r = get_text(url)
    assert_includes(r, 'T0014', "應含 T0014")
  end

  def test_download
    url = "download/html/T0262_005.html"
    html = get_text(url)
    row = <<~HTML
      <div class='lg-cell'>欲說是經，</div>
      <div class='lg-cell'>應入行處，</div>
      <div class='lg-cell'>及親近處。</div>
    HTML
    assert_includes(html, row, "下載 T0262_005.html 偈頌應分三欄")

    row = <<~HTML
      <div class='lg-cell'>明珠賜之。</div>
      <div class='lg-cell'>如來亦爾，</div>
    HTML
    assert_includes(html, row, "下載 T0262_005.html 偈頌應分三欄")

    url = "download/html/T0297_001.html"
    html = get_text(url)
    assert_includes(html, '大正新脩大藏經', "下載 T0297_001.html 應包含 字串：《大正新脩大藏經》")

    url = "download/docusky/A1057_001.docusky.xml"
    xml = get_text(url)
    refute_empty(xml)
  end

  def test_dynasty
    url = "download/stat/dynasty-all.csv"
    text = get_text(url)
    
    refute_includes(text, '後漢', "不應有「後漢」，應統一為「東漢」")
  end

  def test_dynasty_works
    url = "download/scope-selector/dynasty-works.json"
    
    r = get_json(url)
    refute_nil(r, "錯誤：回傳 nil, url: #{url}")
    if r
      data = r.dig(0, 'children', 0)
      refute_includes(data, '後漢', "不應有「後漢」，應統一為「東漢」")
    end
  end

  def test_check_list_j
    url = 'download/check-list-J.csv'
    data = get_text(url)
    assert_operator(data, :start_with?, '經號,經名,卷次')  
  end

  def test_g
    url = "download/html/X0329_002.html"
    html = get_text(url)
    File.write(File.join(TMP_DIR, 'X0329_002.html'), html)
    regexp = /<span class="gaiji" data-gid="CB01919">糓<\/span>/
    assert_match(regexp, html, '缺字呈現錯誤')
  end

  def test_scope
    url = "download/scope-selector/vol.json"    
    r = get_json(url)
    refute_nil(r, "錯誤：回傳 nil, url: #{url}")

    if r
      root = r.first
      root['children'].each do |h|
        refute_empty(h['children'], "#{h['title']} 的 children 不應該是空的")
      end
    end
  end
end
