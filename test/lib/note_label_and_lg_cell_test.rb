require 'test_helper'
require Rails.root.join('lib/cbeta_p5a_share')
require Rails.root.join('lib/tasks/x2h_share')

class NoteLabelAndLgCellTest < ActiveSupport::TestCase
  class NoteConverter
    include CbetaP5aShare

    attr_reader :block_notes

    def initialize(format)
      @format = format
      @params = { notes: true }
      @mod_notes = Set.new
      @notes_mod = { 1 => {} }
      @juan = 1
      @block_notes = []
    end

    def traverse(_e, _mode) = '校注文字'
  end

  class LgConverter
    include P5aToHtmlShare

    def line_space(n) = '　' * n.to_i
  end

  def note(subtype)
    attrs = subtype ? " subtype='#{subtype}'" : ''
    Nokogiri::XML("<note n='0001001'#{attrs}/>").root
  end

  # 原本 text 模式只在非 標/解/科 時換成純編號, 會輸出 [ data-label='標01']
  test 'text 模式的 標/解/科 註標是純文字' do
    { 'biao' => '標01', 'jie' => '解01', 'ke' => '科01', nil => '1' }.each do |subtype, label|
      c = NoteConverter.new('text')

      assert_equal "[#{label}]", c.ele_note_orig(note(subtype), nil), subtype.inspect
      assert_equal [ "[#{label}] 校注文字" ], c.block_notes
    end
  end

  test 'html 模式的 標 註標帶 data-label' do
    html = NoteConverter.new('html').ele_note_orig(note('biao'), nil)

    assert_equal "<a class='noteAnchor' href='#n0001001' data-label='標01'></a>", html
  end

  # 第二次 match (text-indent) 原本會蓋掉 $1, 輸出 <div class='lg-cell' 1>
  test 'lg-cell 保留 caesura 的 style' do
    l = Nokogiri::XML('<lg><l/></lg>').at('l')
    s = '甲<caesura style="text-indent:1em;"/>乙'

    html = LgConverter.new.e_l_regular_cells(s, l)

    assert_includes html, %(<div class='lg-cell' style="text-indent:1em;">乙</div>)
  end
end
