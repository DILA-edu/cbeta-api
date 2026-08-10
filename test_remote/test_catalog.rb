class CatalogTest < Minitest::Test
  def setup
    @url = "catalog_entry"
  end

  def test_cbeta
    params = { q: 'CBETA' }
    r = get_json(@url, params)
    assert_equal(23, r['num_found'])

    params = { q: 'CBETA.023.006.003' }
    r = get_json(@url, params)
    label = r['results'][0]['label']
    refute_operator(label, :end_with?, '（上）')
  end

  def test_cn
    save_referer = $referer
    $referer = 'https://cbetaonline.cn/'

    r = get_json(@url, q: 'vol')
    a = r['results'].select { |x| x['n']=='Vol-Y'}
    assert_empty(a, 'cbetaonline.cn 要過濾 Y')

    r = get_json(@url, q: 'CBETA.023')
    a = r['results'].select { |x| x['label'].include?('印順') }
    assert_empty(a, 'cbetaonline.cn 要過濾 Y')
    
    r = get_json(@url, q: 'orig.006')
    a = r['results'].select { |x| x['n'] == 'orig-Y' }
    assert_empty(a, 'cbetaonline.cn 要屏蔽 Y')

    a = r['results'].select { |x| x['n'] == 'orig-YP' }
    refute_empty(a, 'cbetaonline.cn 不要屏蔽 YP')

    $referer = save_referer
  end
  
  def test_y
    params = { q: 'orig-Y.003' }
    data = get_json(@url, params)
    assert_equal('Y0030 雜阿含經論會編', data.dig('results', 0, 'label'))
  end
end
