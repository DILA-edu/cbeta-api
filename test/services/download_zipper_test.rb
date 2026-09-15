# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'zip'

class DownloadZipperTest < ActiveSupport::TestCase
  RELEASE = '2026r2'
  FILELIST = "cbeta_odt_#{RELEASE}/filelist_#{RELEASE}.txt"

  test "一經一個 zip, 內部路徑為 <work>/<檔名>" do
    with_download_dir do |dir|
      DownloadZipper.new(:odt, download_dir: dir).zip

      assert_equal ['T0001/T0001_001.odt', 'T0001/T0001_002.odt'], entries(dir, 'odt/T/T0001.zip')
      assert_equal ['X1600/X1600_001.odt'], entries(dir, 'odt/X/X1600.zip')
    end
  end

  test "bundle 產生全套打包檔, 內部路徑帶 cbeta_<format>_<季別>/ 前綴" do
    with_download_dir do |dir, catalog|
      DownloadZipper.new(:odt, bundle: true, download_dir: dir, release: RELEASE,
                        catalog_dir: catalog).zip

      bundle = dir.join('cbeta-odt.zip')
      assert_predicate bundle, :exist?
      assert_equal %w[cbeta_odt_2026r2/T/T0001/T0001_001.odt cbeta_odt_2026r2/T/T0001/T0001_002.odt
                    cbeta_odt_2026r2/X/X1600/X1600_001.odt],
                   entries(dir, 'cbeta-odt.zip') - [FILELIST]

      Zip::File.open(bundle) do |zip|
        assert_equal '甲', zip.read('cbeta_odt_2026r2/T/T0001/T0001_001.odt').force_encoding('UTF-8')
      end

      # 一經一檔的 zip 不會被收進全套打包檔
      assert_empty entries(dir, 'cbeta-odt.zip').grep(/\.zip\z/)
    end
  end

  test "沒有 bundle 時不產生全套打包檔" do
    with_download_dir do |dir|
      DownloadZipper.new(:odt, download_dir: dir).zip

      assert_not dir.join('cbeta-odt.zip').exist?
    end
  end

  test "重跑會重建 zip, 不會因 entry 重複而失敗" do
    with_download_dir do |dir, catalog|
      2.times { DownloadZipper.new(:odt, bundle: true, download_dir: dir, release: RELEASE,
                        catalog_dir: catalog).zip }

      assert_equal ['T0001/T0001_001.odt', 'T0001/T0001_002.odt'], entries(dir, 'odt/T/T0001.zip')
      assert_equal 4, entries(dir, 'cbeta-odt.zip').size
      assert_not dir.join('cbeta-odt.zip.tmp').exist?
    end
  end

  test "重跑會換掉舊的全套打包檔" do
    with_download_dir do |dir, catalog|
      dir.join('cbeta-odt.zip').write('舊版')
      DownloadZipper.new(:odt, bundle: true, download_dir: dir, release: RELEASE,
                        catalog_dir: catalog).zip

      assert_equal 4, entries(dir, 'cbeta-odt.zip').size
    end
  end

  test "全套打包檔收錄經號對照表, 只收這次打包進去的經號" do
    with_download_dir do |dir, catalog|
      DownloadZipper.new(:odt, bundle: true, download_dir: dir, release: RELEASE,
                         catalog_dir: catalog).zip

      assert_includes entries(dir, 'cbeta-odt.zip'), FILELIST
      Zip::File.open(dir.join('cbeta-odt.zip')) do |zip|
        text = zip.read(FILELIST).force_encoding('UTF-8')
        assert_equal ['T0001 , 01 , 22 , 長阿含經 , 後秦 佛陀耶舍共竺佛念譯',
                      'X1600 , 88 , 1 , 東國僧尼錄 , '],
                     text.split("\r\n").drop(2)
      end
    end
  end

  test "一經一檔的 zip 不收經號對照表" do
    with_download_dir do |dir, catalog|
      DownloadZipper.new(:odt, bundle: true, download_dir: dir, release: RELEASE,
                         catalog_dir: catalog).zip

      assert_equal ['T0001/T0001_001.odt', 'T0001/T0001_002.odt'], entries(dir, 'odt/T/T0001.zip')
    end
  end

  test "docx 只打包 docx, 不會撈到同層的 odt" do
    with_download_dir(:docx) do |dir, catalog|
      # 同一個 download 目錄下兩種格式並存
      with_files(dir, :odt)
      DownloadZipper.new(:docx, bundle: true, download_dir: dir, release: RELEASE,
                        catalog_dir: catalog).zip

      assert_equal %w[cbeta_docx_2026r2/T/T0001/T0001_001.docx cbeta_docx_2026r2/T/T0001/T0001_002.docx
                    cbeta_docx_2026r2/X/X1600/X1600_001.docx],
                   entries(dir, 'cbeta-docx.zip') - ['cbeta_docx_2026r2/filelist_2026r2.txt']
      assert_not dir.join('cbeta-odt.zip').exist?
    end
  end

  private

  def with_download_dir(format = :odt)
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      with_files(root, format)
      yield root, with_catalog(root)
    end
  end

  # authority catalog 一個藏經一個 json, 經號對照表由此產生
  def with_catalog(root)
    catalog = root.join('authority')
    catalog.mkpath
    catalog.join('T.json').write({
      'T0001' => { 'vol' => 'T01', 'juans' => 22, 'title' => '長阿含經',
                   'byline' => '後秦 佛陀耶舍共竺佛念譯' }
    }.to_json)
    catalog.join('X.json').write({
      'X1600' => { 'vol' => 'X88', 'juans' => 1, 'title' => '東國僧尼錄' }
    }.to_json)
    catalog
  end

  def with_files(root, format)
    {
      "#{format}/T/T0001/T0001_001.#{format}" => '甲',
      "#{format}/T/T0001/T0001_002.#{format}" => '乙',
      "#{format}/X/X1600/X1600_001.#{format}" => '丙'
    }.each do |path, content|
      file = root.join(path)
      file.dirname.mkpath
      file.write(content)
    end
  end

  def entries(dir, name)
    Zip::File.open(dir.join(name)) { |zip| zip.entries.map(&:name).sort }
  end
end
