require "test_helper"

class DownloadTextsTest < ActionDispatch::IntegrationTest
  test "download text" do
    zip_file = Rails.root.join('public', "download/text/T2782.txt.zip")
    Zip::File.open(zip_file) do |z|
      text = z.read('T2782_001.txt').force_encoding('UTF-8')
      assert text.include?('覺不堅為堅　　善住於顛倒'), "偈頌之間要空格, #{zip_file}"
    end
  end
end
