# encoding: utf-8
require 'cbeta'
require 'json'

class CRF
  PUNCS = ' .()[]-　．。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—◎'

  def initialize(base)
    @base = base
    fn = File.join(base, 'dicts/words.json')
    @words = JSON.parse(File.read(fn))

    read_dila_words
  end

  def self.chars_in_file(fn)
    text = File.read(fn)
    text.gsub!("\n", "")
    text.gsub!('/', '')
    text.size
  end

  def self.chars_in_result_file(fn)
    i = 0
    File.foreach(fn) do |line|
      line.chomp!
      next if line.empty?
      i += 1
    end
    i
  end

  def tag_file(fn, mode=3)
    basename = File.basename(fn)
    text = File.read(fn)
    text.gsub!(/\n/, "/\n/")
    text.gsub!(/\/{2,}/, '/')
  
    a = text.split('/')
    r = ''
    a.each do |s|
      next if s.empty?
      if s == "\n"
        r += "\n"
      else
        case mode
        when 1
          r += tag_string(s)
        when 2
          r += tag_string2(s)
        when 3
          r += tag_string3(s)
        end
      end
    end
    r.gsub!(/\n{3,}/, "\n\n")
    r
  end

  # 將 某個字串轉為 一字一行的 CRF tag 格式
  # tag: S, B, M1, M2, M, E
  def tag_string(s)
    return '' if s.empty?
    r = ''
    if s.match(/^\d+$/)
      r += "#{s} num S\n"
    elsif s.match(/^[a-zA-Z]+$/)
        r += "#{s} en S\n"
    elsif s.match(/^[ \.\(\)\[\]\-　．。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—◎]+$/)
      r += "\n#{s} PUNC S\n\n"
    else
      a = s.scan(/\{CB\d{5}\}|./) # 缺字要當做一個字
      case a.size
      when 1
        r += "#{s} zh S\n"
      when 2
        r += "#{a[0]} zh B\n"
        r += "#{a[-1]} zh E\n"
      when 3
        r += "#{a[0]} zh B\n"
        r += "#{a[1]} zh M\n"
        r += "#{a[-1]} zh E\n"
      when 4
        r += "#{a[0]} zh B\n"
        r += "#{a[1]} zh M1\n"
        r += "#{a[2]} zh M\n"
        r += "#{a[-1]} zh E\n"
      else
        r += "#{a[0]} zh B\n"
        r += "#{a[1]} zh M1\n"
        r += "#{a[2]} zh M2\n"
        (3..(a.size-2)).each do |i|
          r += "#{a[i]} zh M\n"
        end
        r += "#{a[-1]} zh E\n"
      end
    end
    r
  end

  # 將 某個字串轉為 一字一行的 CRF tag 格式
  # tag: S, B, I, E
  def tag_string2(s)
    return '' if s.empty?
    r = ''
    if s.match(/^\d+$/)
      r += "#{s} num S\n"
    elsif s.match(/^[a-zA-Z]+$/)
        r += "#{s} en S\n"
    elsif s.match(/^[ \.\(\)\[\]\-　．。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—◎]+$/)
      r += "\n#{s} PUNC S\n\n"
    else
      a = s.scan(/\{CB\d{5}\}|./) # 缺字要當做一個字
      case a.size
      when 1
        r += "#{s} zh S\n"
      when 2
        r += "#{a[0]} zh B\n"
        r += "#{a[-1]} zh E\n"
      else
        r += "#{a[0]} zh B\n"
        (1..(a.size-2)).each do |i|
          r += "#{a[i]} zh I\n"
        end
        r += "#{a[-1]} zh E\n"
      end
    end
    r
  end

  # 將 某個字串轉為 一字一行的 CRF tag 格式
  # features:
  #   1: num, en, PUNC, zh
  #   2: DILA 語料庫
  #   3: 佛光大辭典
  #   4: 丁福保詞典
  #   5: 教育部國語詞典
  #   6: S, B, I, E
  def tag_string3(s, mode='learn')
    return '' if s.empty?
    
    r = ''
    if s.match(/^\d+$/)
      r = "#{s} num N N N N"
      r += " S" if mode == 'learn'
      return r + "\n"
    end

    if s.match(/^[a-zA-Z]+$/)
      r = "#{s} en N N N N"
      r += " S" if mode == 'learn'
      return r + "\n"
    end

    if s.match(/^[ \.\(\)\[\]\-　．。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—◎]+$/)
      r = "\n#{s} PUNC N N N N"
      r += " S" if mode == 'learn'
      return r + "\n\n"
    end

    tag_zh_str(s, mode)
  end

  private

  def get_features(str, chars_features)
    (0..str.size-2).each do |i|
      get_features_from_dicts(str[i..-1], chars_features[i..-1])
    end
  end

  def get_features_from_dicts(str, chars_features)
    first_char = str[0]
    terms = @words[first_char]
    return if terms.nil?

    terms.each_pair do |k,v|
      next if str.size < k.size
      next unless str.start_with? k

      # 'B' 表示可以跟後一個字連在一起
      update_features(chars_features[0], v, 'B')

      # 'I' 表示跟前面、後面都可以連
      (1..k.size-2).each do |i|
        update_features(chars_features[i], v, 'I')
      end

      # 'E' 表示可以跟前一個字連在一起
      update_features(chars_features[k.size-1], v, 'E')
    end
  end

  def read_dila_words
    s = File.read(File.join(@base, 'dicts/dila.json'))
    a = JSON.parse(s)
    a.each do |s|
      terms = s.split('/')
      terms.each do |t|
        next if t.size < 2
        first_char = t[0]
        unless @words.key? first_char
          @words[first_char] = {}
        end
        target = @words[first_char]
        if target.key? t
          target[t] << 'dila'
        else
          target[t] = ['dila']
        end
      end
    end
  end

  def tag_zh_str(str, mode)
    s = str.gsub(/[\n\r]+/m, "\u2028") # Unicode Character 'LINE SEPARATOR'
    if s.size == 1
      r = "#{s} zh N N N N"
      r += " S" if mode == 'learn'
      r += "\n"
      return r
    end

    # 缺字 取代為 PUA
    s.gsub!(/\{(CB\d{5})\}/) do
      CBETA.pua($1)
    end

    chars_features = Array.new(s.size) do
      {
        'dila' => 'N',
        'fk' => 'N',
        'gy' => 'N',
        'ch' => 'N'
      }
    end

    get_features(s, chars_features)
    r = ''
    chars_features.each_index do |i|
      f = chars_features[i]
      r += s[i] + " zh"
      r += ' ' + f['dila']
      r += ' ' + f['fk']
      r += ' ' + f['gy']
      r += ' ' + f['ch']
      if mode == 'learn'
        if i == 0
          r += " B"
        elsif i == (s.size-1)
          r += " E"
        else
          r += " I"
        end
      end
      r += "\n"
    end
    r
  end

  def update_features(features, dicts, feature)
    dicts.each do |d|
      case features[d]
      when 'B'
        case feature
        when 'E', 'I'
          features[d] = 'I'
        end
      when 'E'
        case feature
        when 'B', 'I'
          features[d] = 'I'
        end
      when 'I'
      when 'N'
        features[d] = feature
      else
        abort "error line: #{__LINE__}"
      end
    end
  end
end

if __FILE__ == $0
  crf = CRF.new
  a = %w(鞭{CB02304} 一一 一一心中 亦不能自證得阿耨多羅三藐三菩提)
  a.each do |s|
    puts '-' * 10
    puts s
    puts crf.tag_string3(s)
  end
end