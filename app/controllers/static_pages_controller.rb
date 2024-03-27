class StaticPagesController < ApplicationController
  def callback
  end
    
  def download_ebooks
  end
  
  def get_html
  end
  
  def goto
    # Todo: 
    #   * 宗鑑，《釋門正統》，R130, p. 861b7
    #   * 《羅湖野錄》，《續藏經》冊142，頁1003b
    @cit_formats = [
      'T51, no. 2087, pp. 868-888',
      'T46, no. 1911, p. 18c',
      'T2, no. 150A, p. 878a24',
      'T15, no. 602, p. 64a14-b26.',
      'T15, no. 606, pp. 215c22-216a2.',
      '《大正藏》冊47，第1969 號',
      '《大正藏》冊47，第1970 號，卷6',
      '《大正藏》冊19，第974C 號，頁386',
      '《大正藏》冊55，第2154 號，頁565a',
      '《續藏經》冊142，頁1003b',
      'R130',
      'R101, p. 53b',
      'R130, p. 861b7'
    ]
  end
  
  def kwic
  end
  
  def home
  end
  
  def line
  end
  
  def scope_selector
  end

  def search_similar
    @examples = [
      '已得善提捨不證', 
      '菩薩清涼月，遊於畢竟空，垂光照三界，心法無不現。', 
      '諸惡莫作，眾善奉行，自淨其意，是諸佛教', 
      '斷愛欲，轉諸結，慢無間等，究竟苦邊',
      '若人欲了知，三世一切佛，應觀法界性，一切唯心造',
      '是日已過，命亦隨減，如少水魚，斯有何樂'
    ]
  end

  def work
  end
end
