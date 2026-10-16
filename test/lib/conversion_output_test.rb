require 'test_helper'

class ConversionOutputTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir)
    @tmp = @root.join('tmp')
    @dest = @root.join('dest')

    write(@dest.join('T/T0001/old.txt'), 'old T')
    write(@dest.join('X/X0001/x.txt'), 'X')
    write(@tmp.join('T/T0001/new.txt'), 'new T')
  end

  teardown { @root.rmtree }

  test '全部轉檔時以 tmpdir 取代 dest' do
    capture_io { ConversionOutput.install(@tmp, @dest, partial: false) }

    assert @dest.join('T/T0001/new.txt').exist?
    refute @dest.join('X/X0001/x.txt').exist?
    refute @dest.join('T/T0001/old.txt').exist?
    refute @tmp.exist?
  end

  test '只轉部分時合併進 dest, 保留其他部分' do
    write(@dest.join('T/T0001/new.txt'), 'stale')

    capture_io { ConversionOutput.install(@tmp, @dest, partial: true) }

    assert_equal 'new T', @dest.join('T/T0001/new.txt').read
    assert_equal 'X', @dest.join('X/X0001/x.txt').read
    refute @tmp.exist?
  end

  test '只轉部分且 dest 不存在時照樣建立' do
    @dest.rmtree

    capture_io { ConversionOutput.install(@tmp, @dest, partial: true) }

    assert_equal 'new T', @dest.join('T/T0001/new.txt').read
  end

  private

  def write(path, content)
    path.dirname.mkpath
    path.write(content)
  end
end
