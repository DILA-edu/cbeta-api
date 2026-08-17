# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'zip'

class DownloadZipperTest < ActiveSupport::TestCase
  test "一經一個 zip, 內部路徑為 <work>/<檔名>" do
    with_download_dir do |dir|
      DownloadZipper.new(:odt, download_dir: dir).zip

      assert_equal ['T0001/T0001_001.odt', 'T0001/T0001_002.odt'], entries(dir, 'odt/T/T0001.zip')
      assert_equal ['X1600/X1600_001.odt'], entries(dir, 'odt/X/X1600.zip')
    end
  end

  test "bundle 產生全套打包檔, 內部路徑帶 odt/ 前綴" do
    with_download_dir do |dir|
      DownloadZipper.new(:odt, bundle: true, download_dir: dir).zip

      bundle = dir.join('cbeta-odt.zip')
      assert_predicate bundle, :exist?
      assert_equal %w[odt/T/T0001/T0001_001.odt odt/T/T0001/T0001_002.odt odt/X/X1600/X1600_001.odt],
                   entries(dir, 'cbeta-odt.zip')

      Zip::File.open(bundle) do |zip|
        assert_equal '甲', zip.read('odt/T/T0001/T0001_001.odt').force_encoding('UTF-8')
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
    with_download_dir do |dir|
      2.times { DownloadZipper.new(:odt, bundle: true, download_dir: dir).zip }

      assert_equal ['T0001/T0001_001.odt', 'T0001/T0001_002.odt'], entries(dir, 'odt/T/T0001.zip')
      assert_equal 3, entries(dir, 'cbeta-odt.zip').size
      assert_not dir.join('cbeta-odt.zip.tmp').exist?
    end
  end

  test "重跑會換掉舊的全套打包檔" do
    with_download_dir do |dir|
      dir.join('cbeta-odt.zip').write('舊版')
      DownloadZipper.new(:odt, bundle: true, download_dir: dir).zip

      assert_equal 3, entries(dir, 'cbeta-odt.zip').size
    end
  end

  private

  def with_download_dir
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      {
        'odt/T/T0001/T0001_001.odt' => '甲',
        'odt/T/T0001/T0001_002.odt' => '乙',
        'odt/X/X1600/X1600_001.odt' => '丙'
      }.each do |path, content|
        file = root.join(path)
        file.dirname.mkpath
        file.write(content)
      end

      yield root
    end
  end

  def entries(dir, name)
    Zip::File.open(dir.join(name)) { |zip| zip.entries.map(&:name).sort }
  end
end
