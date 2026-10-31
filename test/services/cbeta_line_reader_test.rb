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
end
