require 'test_helper'

class CbetaLineReaderTest < ActiveSupport::TestCase
  # 卍續藏 XML 夾著新文豐版 (R) 的 lb; 原本會當成新的一行, 文字記到 R 的行號下
  test '只取本藏的 lb' do
    Dir.mktmpdir do |dir|
      fn = File.join(dir, 'X01n0001.xml')
      File.write(fn, <<~XML)
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>
          <lb n="0001a01" ed="X"/>甲乙
          <lb n="0001a02" ed="X"/><lb n="0705a01" ed="R150"/>丙丁
          <lb n="0001a03" ed="X" type="old"/>戊
        </body></text></TEI>
      XML

      lines = CbetaLineReader.new({}).read(fn)

      assert_equal %w[0001a01 0001a02], lines.keys
      assert_equal '丙丁戊', lines['0001a02'].strip.delete(' ')
    end
  end

  # YP30 表格 cell 內的強制換行: 沒有 n 也沒有 ed, 原本會把後面的文字記到 nil 行號下
  test 'lb type=forced 不是新的一行' do
    Dir.mktmpdir do |dir|
      fn = File.join(dir, 'YP30n0031.xml')
      File.write(fn, <<~XML)
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>
          <lb ed="YP" n="0013a02"/>甲<lb type="forced"/>乙
          <lb ed="YP" n="0013a03"/>丙
        </body></text></TEI>
      XML

      lines = CbetaLineReader.new({}).read(fn)

      assert_equal %w[0013a02 0013a03], lines.keys
      assert_equal '甲乙', lines['0013a02'].strip.delete(" \n")
    end
  end
end
