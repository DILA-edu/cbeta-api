class HelpTest < Minitest::Test
  def test_help
    url = "help/other/T48/T2007_ps.htm"
    r = get_text(url)
    refute_nil(r)
  end 
end
