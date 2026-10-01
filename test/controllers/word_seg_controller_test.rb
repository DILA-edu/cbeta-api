require 'test_helper'

class WordSegControllerTest < ActionDispatch::IntegrationTest
  test 'word_seg 缺少 t 時回傳純文字訊息，不是整頁 HTML' do
    get '/word_seg'

    assert_response :success
    assert_equal '缺少 t 參數', response.body
  end

  # WordSegService 的 errors 可能含暫存檔路徑或斷詞程式的 stderr
  class FailingWordSeg
    def run(_) = OpenStruct.new(success?: false, errors: '寫檔發生錯誤: /tmp/secret/path')
  end

  test 'word_seg2 分詞失敗時不回傳內部錯誤細節' do
    replace_new(WordSegService, FailingWordSeg.new) do
      get '/word_seg2', params: { payload: '觀自在菩薩' }
    end

    assert_equal({ 'error' => { 'code' => 500, 'message' => '斷詞失敗' } }, response.parsed_body)
  end

  private

  # Minitest 6 的 stub 已拆到 minitest-mock gem，這裡自己暫時換掉 .new。
  def replace_new(klass, instance)
    klass.define_singleton_method(:new) { |*, **| instance }
    yield
  ensure
    klass.singleton_class.remove_method(:new)
  end
end
