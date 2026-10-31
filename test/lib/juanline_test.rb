require 'test_helper'

# `Juanline` 定義在 lib/tasks/convert/juanline.rake, `ImportJuanLine` 在 lib/tasks/import/juan_line.rake
Rails.application.load_tasks unless defined?(Juanline) && defined?(ImportJuanLine)

class JuanlineTest < ActiveSupport::TestCase
  XML = <<~XML.freeze
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0"><text><body>
    %s
    </body></text></TEI>
  XML

  # 卷 3 由 X39 接到 X40: 後一冊的 XML 會再出現同一卷的 milestone,
  # 原本直接覆寫, 前半冊的起始行號因此遺失
  test 'convert:juanline 卷跨冊時一冊一段' do
    Dir.mktmpdir do |dir|
      write(dir, 'X39', <<~BODY)
        <milestone unit="juan" n="2"/><lb n="0788c01" ed="X"/>甲<lb n="0876c03" ed="X"/>乙
        <milestone unit="juan" n="3"/><lb n="0876c04" ed="X"/>丙<lb n="0876c05" ed="R123"/><lb n="0898a08" ed="X"/>丁
      BODY
      write(dir, 'X40', <<~BODY)
        <milestone unit="juan" n="3"/><lb n="0001a01" ed="X"/>戊<lb n="0074b10" ed="X"/>己
      BODY

      juans = convert(dir)

      assert_equal [ { vol: 'X39', lb_begin: '0788c01', lb_end: '0876c03' } ], juans['2']
      assert_equal [ { vol: 'X39', lb_begin: '0876c04', lb_end: '0898a08' },
                     { vol: 'X40', lb_begin: '0001a01', lb_end: '0074b10' } ], juans['3']
    end
  end

  test 'import:juanline 一段一列, uuid 只放在第一段' do
    importer = ImportJuanLine.allocate
    importer.instance_variable_set(:@juan_uuids, {
      'X0714_003' => { 'juan_uuid' => 'j3', 'content_uuid' => 'c3' }
    })
    importer.instance_variable_set(:@inserts, [])
    importer.instance_variable_set(:@uuids, Set.new)
    importer.instance_variable_set(:@vol_lbs, Set.new)
    importer.instance_variable_set(:@work, 'X0714')

    Tempfile.create([ 'X0714', '.json' ]) do |f|
      f.write({ '3' => [ { vol: 'X39', lb_begin: '0876c04', lb_end: '0898a08' },
                         { vol: 'X40', lb_begin: '0001a01', lb_end: '0074b10' } ] }.to_json)
      f.flush
      importer.send(:import_file, f.path)
    end

    rows = importer.instance_variable_get(:@inserts)
    assert_equal([ [ 'X39', 1, '0876c04', 'j3', 'c3' ], [ 'X40', 2, '0001a01', nil, nil ] ],
                 rows.map { it.values_at(:vol, :seq, :lb, :uuid, :content_uuid) })
  end

  private

  def write(dir, vol, body)
    folder = File.join(dir, 'X', vol)
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "#{vol}n0714.xml"), format(XML, body))
  end

  def convert(dir)
    converter = Juanline.new
    converter.instance_variable_set(:@in, dir)
    converter.instance_variable_set(:@juanline, {})
    %w[X39 X40].each { |vol| converter.send(:handle_vol, 'X', vol) }
    converter.instance_variable_get(:@juanline)['X0714']
  end
end
