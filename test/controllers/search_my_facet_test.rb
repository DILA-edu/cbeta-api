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
end
