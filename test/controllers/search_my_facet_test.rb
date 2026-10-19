require 'test_helper'

# NEAR / Exclude 的 facet 在 Ruby 端逐卷累加 (my_facet)
class SearchMyFacetTest < ActiveSupport::TestCase
  setup do
    @controller = SearchController.new
    @controller.instance_variable_set(:@canon_name, {})
    @controller.define_singleton_method(:action_name) { 'all_in_one' }
  end

  test 'Canon 表查不到的藏經不給 canon_name, 不讓整個請求失敗' do
    Canon.create!(id2: 'T', name: '大正藏')
    dest = {}

    @controller.send(:my_facet_canon, { canon: 'T', term_hits: 2 }, dest)
    @controller.send(:my_facet_canon, { canon: 'ZZ', term_hits: 3 }, dest)
    @controller.send(:my_facet_canon, { canon: 'ZZ', term_hits: 1 }, dest)

    assert_equal({ canon: 'T', canon_name: '大正藏', hits: 2, docs: 1 }, dest['T'])
    assert_equal({ canon: 'ZZ', hits: 4, docs: 2 }, dest['ZZ'])
  end

  test 'notes 的 Exclude facet: key 順序同 es_facets, 依 hits 遞減、朝代依朝代順序' do
    @controller.define_singleton_method(:action_name) { 'notes' }
    @controller.instance_variable_set(:@dynasty_order, { '東漢' => 1, '唐' => 2 })
    @controller.define_singleton_method(:read_dynasty_order) { nil }
    row = ->(canon, dynasty, hits) { { canon:, category: '', creators_with_id: '', dynasty:, work: 'T0001', title: 't', term_hits: hits } }

    f = @controller.send(:notes_my_facet, [ row.('T', '唐', 1), row.('X', '東漢', 5), row.('X', '唐', 2) ])

    assert_equal %w[category creator dynasty work canon], f.keys
    assert_equal(%w[X T], f['canon'].map { it[:canon] })
    assert_equal([ 7, 1 ], f['canon'].map { it[:hits] })
    assert_equal([ 2, 1 ], f['canon'].map { it[:docs] })
    assert_equal(%w[東漢 唐], f['dynasty'].map { it[:dynasty] })
  end
end
