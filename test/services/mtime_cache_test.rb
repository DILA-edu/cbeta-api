require 'test_helper'

class MtimeCacheTest < ActiveSupport::TestCase
  setup do
    MtimeCache.clear
    @dir = Pathname.new(Dir.mktmpdir)
    @file = @dir.join('a.json')
    @file.write('{"v":1}')
  end

  teardown do
    MtimeCache.clear
    @dir.rmtree
  end

  test '檔案沒變時不重算' do
    calls = 0
    2.times { MtimeCache.fetch(:t, @file) { calls += 1 } }

    assert_equal 1, calls
  end

  test '檔案變動 (季度更新資料未重啟) 時重新產生' do
    read = -> { MtimeCache.fetch(:t, @file) { JSON.parse(@file.read) } }
    assert_equal 1, read.call['v']

    @file.write('{"v":22}')
    File.utime(Time.now + 5, Time.now + 5, @file)

    assert_equal 22, read.call['v']
  end

  test '不同 key 互不影響' do
    assert_equal :a, MtimeCache.fetch(:a, @file) { :a }
    assert_equal :b, MtimeCache.fetch(:b, @file) { :b }
  end

  test 'openapi 的快取值不會被 request 改到' do
    get_spec = -> { MtimeCache.fetch(:openapi_spec, OpenapiController::SPEC_PATH) { YAML.safe_load_file(OpenapiController::SPEC_PATH, freeze: true) } }
    spec = get_spec.call

    assert spec.frozen?
    assert spec['info'].frozen?
  end
end
