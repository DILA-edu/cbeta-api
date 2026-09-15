# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class DownloadFilelistTest < ActiveSupport::TestCase
  test "標題列、分隔線、5 欄逗號分隔, 以 CRLF 換行且檔尾不換行" do
    with_catalog do |dir|
      text = DownloadFilelist.new(%w[T0001], catalog_dir: dir).to_s

      assert_equal "經號 , 冊數 , 卷數 , 經名 , 作譯者\r\n#{'=' * 55}\r\n" \
                   "T0001 , 01 , 22 , 長阿含經 , 後秦 佛陀耶舍共竺佛念譯",
                   text
    end
  end

  test "跨冊的冊數寫成範圍, 藏經代碼不出現在冊數" do
    with_catalog do |dir|
      assert_includes rows(dir, %w[T0220]), 'T0220 , 05-07 , 600 , 大般若波羅蜜多經 , 唐 玄奘譯'
    end
  end

  test "沒有作譯者時最後一欄留空" do
    with_catalog do |dir|
      assert_includes rows(dir, %w[X1671]), 'X1671 , 88 , 1 , 東國僧尼錄 , '
    end
  end

  test "依經號排序, 不受傳入順序影響" do
    with_catalog do |dir|
      ids = rows(dir, %w[X1671 T0220 T0001]).map { |r| r.split(' , ').first }

      assert_equal %w[T0001 T0220 X1671], ids
    end
  end

  test "catalog 查無的經號略過, 其餘照常產生" do
    with_catalog do |dir|
      ids = rows(dir, %w[T0001 T9999]).map { |r| r.split(' , ').first }

      assert_equal %w[T0001], ids
    end
  end

  test "authority catalog 缺檔時中止, 不產出空的對照表" do
    with_catalog do |dir|
      dir.join('T.json').delete

      assert_raises(RuntimeError) { DownloadFilelist.new(%w[T0001], catalog_dir: dir).to_s }
    end
  end

  private

  def rows(dir, work_ids)
    DownloadFilelist.new(work_ids, catalog_dir: dir).to_s.split("\r\n").drop(2)
  end

  # authority catalog 一個藏經一個 json
  def with_catalog
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      root.join('T.json').write({
        'T0001' => { 'vol' => 'T01', 'juans' => 22, 'title' => '長阿含經',
                     'byline' => '後秦 佛陀耶舍共竺佛念譯' },
        'T0220' => { 'vol' => 'T05..T07', 'juans' => 600, 'title' => '大般若波羅蜜多經',
                     'byline' => '唐 玄奘譯' }
      }.to_json)
      root.join('X.json').write({
        'X1671' => { 'vol' => 'X88', 'juans' => 1, 'title' => '東國僧尼錄' }
      }.to_json)
      yield root
    end
  end
end
