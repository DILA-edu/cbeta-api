# 使用工作檔做測試：ruby test.rb
# 使用正式 production 檔做測試：ruby test.rb p

require 'json'
require 'yaml'

class KwicTest
  def run(env=nil)
    if env == 'p'
      base = Rails.configuration.x.kwic.base
    else
      base = Rails.configuration.x.kwic.temp
    end
    @se = KwicService.new(base)
    
    test_juan
    test_juan_no_kwic
    test_juan_back
    test_work
    test_all
  end

  def test_all
    q = '假人與實陰'
    r = @se.search(q)
    r = r.dig(:results, 0, 'kwic')
    if r.nil? or not r.include? q
      puts r
      puts "error #{__LINE__}"
    end
  
    # 測試 lb 開頭不是數字
    q = '佛教藝術做了很多'
    r = @se.search(q)
    r = r.dig(:results, 0, 'kwic')
    if r.nil? or not r.include? q
      puts r
      puts "error #{__LINE__}"
    end
  end
  
  def test_juan
    puts "test_juan"

    # 跨夾注
    r = @se.search('滅度何等', work: 'T0001', juan: 4)
    unless r[:num_found] > 0
      puts "error #{__LINE__}"
      puts r
    end

    r = @se.search('徑山', work: 'GB0109', juan: 1)
    unless r[:num_found] > 0
      puts r
      puts "error #{__LINE__}"
    end

    r = @se.search('阿含', work: 'T0001', juan: 1)
    unless r[:num_found] == 10
      puts r
      puts "error #{__LINE__}"
    end
    
    r = @se.search('略申', work: 'L1557', juan: 17)
    if r.nil?
      puts "error, return nil, #{__LINE__}"
    else
      kwic = r[:results][0]["kwic"]
      if not kwic.match?(/^.{5}略申.{5}$/)
        puts r
        puts "error #{__LINE__}"
      end
    end
  end
  
  def test_juan_no_kwic
    puts "test_juan_no_kwic"
    r = @se.search('阿含', work: 'T0001', juan: 1, kwic_w_punc: false, kwic_wo_punc: false)
    unless r[:num_found] == 10
      puts r
      puts "error #{__LINE__}"
    end
  end
  
  def test_juan_back
    puts "test_juan_back"
    r = @se.search_juan('阿含', work: 'T0001', juan: 1, sort: 'b')
    unless r.dig(:results, 0, 'kwic') == "o. 1長阿含經序長安釋"
      puts "error #{__LINE__}"
      puts r
    end
  end
  
  def test_work
    puts "test_work"
    r = @se.search('阿含', work: 'T0001', rows: 999999)
    unless r[:num_found] == 74
      puts r
      puts "error #{__LINE__}"
    end
    
    r = @se.search('方正', works: 'T0023')
    unless r[:num_found] > 0
      puts r
      puts "error #{__LINE__}"
    end
  end
end



