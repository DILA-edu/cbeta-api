require 'action_view'
require 'fileutils'
require 'json'
require 'pp'

module Kwic2Helper
  
  # 將數字轉為加上千位號的字串
  def n2c(n)
  	ActionView::Base.new.number_to_currency(n, unit: '', precision: 0)
  end

  class SearchEngine
    attr_reader :config, :size, :text
  
    PUNCS = "\n.()[]-　．。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—"
    
    # param @base [String] suffix array base folder
    def initialize(base)
      @sa_base    = File.join(base, 'sa')   # suffix array folder
      @txt_folder = File.join(base, 'text') # 含有標點的純文字檔
      @encoding_converter = Encoding::Converter.new("UTF-32LE", "UTF-8")
    end
    
    def abs_sa_path(sa_path, name)
      if sa_path.nil?
        Rails.logger.fatal "傳入 abs_sa_path 的 sa_path 參數是 nil, 程式：#{__FILE__}, 行號：#{__LINE__}"
        return nil
      end
      File.join(@sa_base, sa_path, name)
    end
  
    def search(query, args={})
      t1 = Time.now
    
      @option = {
        sort: 'f', # 預設按 keyword 之後的字排序
        edition: 'CBETA', # 預設搜尋 CBETA 版
        rows: 10,
        start: 0,
        around: 5, # 預設顯示關鍵字的前後五個字
        place: false,
        word_count: false,
        mark: false,
        kwic_w_punc: true, # 是否回傳含標點的文字
        kwic_wo_punc: true, # 是否回傳不含標點的文字
        compact: false
      }
      @option.merge! args
      
      if @option[:sort] == 'f'
        q = query
      else
        q = query.reverse
      end
      
      @total_found = 0
      sa_results = search_sa_according_to_option(q)
      
      sa_results = exclude_filter(sa_results, q)
      
      sort_word_count(q, sa_results) if @option[:word_count]
          
      # 根據每頁筆數，只回傳一頁資料
      hits = paginate(q, sa_results)
      
      r = { 
        num_found: @total_found,
        time: Time.now - t1
      }

      if @option[:compact]
        r[:fields] = ['vol', 'work', 'juan', 'lb']
        if @option[:kwic_wo_punc]
          r[:fields] << 'kwic_no_punc'
        end
      end
      
      if @option[:word_count]
        r[:prev_word_count] = @prev_word_count
        r[:next_word_count] = @next_word_count
      end
      
      r[:results] = hits
      r
    end
  
    private
    
    def add_place_info(info_array)
      info_array.each do |data|
        w = Work.find_by n: data['work']
        unless w.nil? or w.place_name.nil?
          data['place_name'] = w.place_name
          data['place_id']   = w.place_id
          data['place_long'] = w.place_long
          data['place_lat']  = w.place_lat
        end
      end
    end
  
    def bsearch(q, left, right)
      return nil if left > right
      middle = (right - left) / 2 + left
      i = sa(middle) # suffix offset
      s = read_str(i, q.size)
      if s == q
        return middle
      elsif middle == left
        return nil if s > q
        return bsearch(q, middle+1, right)
      else
        if s > q
          return bsearch(q, left, middle)
        else
          return bsearch(q, middle, right)
        end
      end
    end
  
    # 在 sa 中搜尋符合 q 的第一筆
    def bsearch_start(q, left, right)
      return right if left >= right
      middle = (right - left) / 2 + left
      i = sa(middle) # suffix offset
      s = read_str(i, q.size)
      if s == q
        return 0 if middle == 0
        i = sa(middle-1) # suffix offset
        s = read_str(i, q.size)
        if s == q
          return bsearch_start(q, left, middle-1)
        else
          return middle
        end
      else
        i = sa(middle+1) # suffix offset
        s = read_str(i, q.size)
        if s == q
          return middle+1
        else
          return bsearch_start(q, middle+1, right)
        end
      end
    end
    
    # 在 sa 中搜尋符合 q 的最後一筆
    def bsearch_stop(q, left, right)
      return left if left >= right
      middle = (right - left) / 2 + left
      i = sa(middle) # suffix offset
      s = read_str(i, q.size)
      if s == q
        return middle if middle == @sa_last
        i = sa(middle+1) # suffix offset
        s = read_str(i, q.size)
        if s == q
          return bsearch_stop(q, middle+1, right)
        else
          return middle
        end
      else
        return left if middle == 0
        i = sa(middle-1) # suffix offset
        s = read_str(i, q.size)
        if s == q
          return middle-1
        else
          return bsearch_stop(q, left, middle-1)
        end
      end
    end
    
    #def compare_result_hit(x, y)
    #  if @option[:sort] == 'f'
    #    a = x['kwic'][-5..-1]
    #    b = y['kwic'][-5..-1]
    #  else
    #    a = x['kwic'][0..4].reverse
    #    b = y['kwic'][0..4].reverse
    #  end
    #  a <=> b
    #end
    
    def exclude_filter(sa_results, q)
      s1 = @option[:negative_lookbehind] # 前面不要出現的字
      s2 = @option[:negative_lookahead]  # 後面不要出現的字
      
      return sa_results if s1.nil? and s2.nil?
      
      @total_found = 0

      if @option[:sort] == 'b'
        s1 = @option[:negative_lookahead].reverse
        s2 = @option[:negative_lookbehind].reverse
      end
      
      s1, n1 = negative_pattern(s1)
      s2, n2 = negative_pattern(s2)
      
      size = n2 + q.size + n1
      
      if not s1.nil? and not s2.nil?
        regexp = Regexp.new("(?<!#{s1})#{q}(?!#{s2})")
      elsif s2.nil?
        regexp = Regexp.new("(?<!#{s1})#{q}")
      else
        regexp = Regexp.new("#{q}(?!#{s2})")
      end
      
      r = []
      sa_results.each do |sa_path, start, found|
        open_files(sa_path)
        a = []
        (0...found).each do |i|
          j = sa(start+i)
          k = j<n1 ? 0 : j-n1
          s = read_str(k, size)
          s.gsub!("\n", '　')
          
          if regexp.match(s)
            if a.empty?
              a << (i..i)
            else
              range = a.last
              if i == (range.end + 1)
                a[-1] = (range.first..i)
              else
                a << (i..i)
              end
            end
          end
        end
        a.each do |range|
          @total_found += range.size
          r << [sa_path, start+range.first, range.size]
        end
      end
      r
    end
  
    #def merge_results(result_array)
    #  r = []
    #  until result_array.empty?
    #    r << result_array.first.first
    #    minimum_index = 0
    #    (1...result_array.size).each do |i|
    #      c = compare_result_hit(r.last, result_array[i].first)
    #      if c > 0
    #        r[-1] = result_array[i].first
    #        minimum_index = i
    #      end
    #    end
    #    result_array[minimum_index].shift
    #    if result_array[minimum_index].empty?
    #      result_array.delete_at(minimum_index)
    #    end
    #  end
    #  r
    #end
    
    def negative_pattern(s)
      r = s
      if s.nil?
        return nil, 0
      elsif s.include? ','
        a = s.split(',')
        r = "(?:%s)" % a.join('|')
        a.collect! { |x| x.size }
        i = a.max
      else
        i = s.size
      end
      return r, i
    end
  
    def open_files(sa_path)
      return false unless open_text(sa_path)
      open_sa   sa_path
      open_info sa_path
      true
    end
  
    def open_info(sa_path)
      if @option[:sort] == 'f'
        fn = abs_sa_path sa_path, 'info.dat'
      else
        fn = abs_sa_path sa_path, 'info-b.dat'
      end
      @f_info = File.open(fn, 'rb')
    end
    
    def open_sa(sa_path)
      if @option[:sort] == 'f'
        fn = abs_sa_path sa_path, 'sa.dat'
      else
        fn = abs_sa_path sa_path, 'sa-b.dat'
      end
      @f_sa = File.open(fn, 'rb')
    end
  
    def open_text(sa_path)
      if @option[:sort] =='f'
        fn = abs_sa_path sa_path, 'all.txt'
      else
        fn = abs_sa_path sa_path, 'all-b.txt'
      end
      return false unless File.exist? fn
      @f_txt = File.open(fn, 'rb')
      @size = @f_txt.size / 4
      @sa_last = @size - 1 # sa 最後一筆的 offset
      true
    end
    
    def paginate(q, sa_results)
      rows = @option[:rows]
      hits = []
      sa_results.each do |sa_path, start, found|
        open_files(sa_path)
        if rows > found
          hits += result_array(q, start, found)
          rows -= found
        else
          hits += result_array(q, start, rows)
          break
        end
      end
      hits
    end
  
    def read_i32(fi, offset)
      fi.seek (offset * 4)
      b = fi.read(4)
      b.unpack('V')[0]
    end
    
    def read_info_block(sa_array, offset, size)
      @f_info.seek (offset * SuffixInfo::SIZE)
      block = @f_info.read(SuffixInfo::SIZE * size)
      r = []
      (0...size).each do |i|
        j = i * SuffixInfo::SIZE
        b = block[j, SuffixInfo::SIZE]
        if @option[:compact]
          a = SuffixInfo::unpack_to_a(b)
          a[3] = "%04d%s%02d" % a[4..6]
          a[4] = sa_array[i]
        else
          a = SuffixInfo::unpack(b)
          a['lb'] = "%04d%s%02d" % [a['page'], a['col'], a['line']]
          a.delete 'page'
          a.delete 'col'
          a.delete 'line'
          a[:sa_offset] = sa_array[i]
        end
        r << a
      end
      r
    end
  
    def read_str(offset, length)
      @f_txt.seek (offset * 4)
      b = @f_txt.read(length * 4)
      @encoding_converter.convert(b)
    end
    
    def read_text_for_info_array(info_array, q)
      pop_size = 3 # 最後 array 要移除幾個不要的元素
      
      if @option[:kwic_wo_punc]
        # 按照文字出現的位置排序，加速文字讀取 IO 速度
        a = info_array.dup
        a.sort! do |x,y|
          (x[0] + x[3]) <=> (y[0] + y[3]) # 0: vol, 4: lb
        end
      
        a.each do |data|      
          data[4] = read_text_wo_punc(data[4], q) # 4: sa offset
        end
        
        pop_size = 2
      end      
      
      info_array.each do |a|
        a.pop(pop_size)
      end
    end
    
    def read_text_for_info_hash(info_array, q)
      if @option[:kwic_w_punc] or @option[:kwic_wo_punc]
        # 按照文字出現的位置排序，加速文字讀取 IO 速度
        a = info_array.dup
        a.sort! do |x,y|
          (x['vol'] + x['lb']) <=> (y['vol'] + y['lb'])
        end
      
        if @option[:kwic_w_punc]
          a.each do |data|      
            data['kwic'] = read_text_with_punc(data, q)
          end
        end
      
        if @option[:kwic_wo_punc]
          a.each do |data|      
            data['kwic_no_punc'] = read_text_wo_punc(data[:sa_offset], q)
          end
        end
      end
      
      info_array.each do |h|
        h.delete 'offset'
        h.delete :sa_offset
      end
      
    end
    
    def read_text_with_punc(data, q)
      i = data['offset']
      
      fn = File.join(@txt_folder, data['vol'], data['work'], '%03d.txt' % data['juan'])
      fi = File.open(fn, 'rb')
      
      r = ''
      
      # 讀 關鍵字 前面的字
      if i < @option[:around]
        b = fi.read(i * 4)
      else
        offset = i - @option[:around]
        fi.seek (offset * 4)
        b = fi.read(@option[:around] * 4)
      end
      
      r += @encoding_converter.convert(b)
      r += '<mark>' if @option[:mark]
      
      # 讀 關鍵字 (可能夾雜標點)
      len = q.size
      while len > 0
        b = fi.read(4)
        break if b.nil?
        c = @encoding_converter.convert(b)
        r += c
        len -= 1 unless PUNCS.include? c
      end
      
      r += '</mark>' if @option[:mark]
      
      # 讀 關鍵字 之後的字
      len = @option[:around] * 4
      b = fi.read(len)
      r += @encoding_converter.convert(b) unless b.nil?
      fi.close
      
      r
    end    
    
    def read_text_wo_punc(offset, q)
      # 讀 關鍵字 之前的字
      if offset < @option[:around]
        s = read_str(0, offset)
      else
        s = read_str(offset - @option[:around], @option[:around])
      end
      
      k = q
      if @option[:mark]
        if @option[:sort] == 'b'
          k = "<mark>%s</mark>" % q.reverse
        else
          k = "<mark>#{q}</mark>"
        end
      end
      
      if @option[:sort] == 'b'
        text = k.reverse + s.reverse
      else
        text = s + k
      end
      
      # 讀 關鍵字 之後的字
      offset += q.size
      s = read_str(offset, @option[:around])
      
      if @option[:sort] == 'b'
        text = s.reverse + text
      else
        text += s
      end
      
      text.gsub("\n", '　')
    end
        
    def result_array(q, start, rows)
      return [] if rows == 0
      
      sa_array = sa_block(start, rows)
      info_array = read_info_block(sa_array, start, rows)
      if @option[:compact]
        read_text_for_info_array(info_array, q)
      else
        read_text_for_info_hash(info_array, q)
        add_place_info(info_array) if @option[:place] # 附上 地理資訊
      end
      info_array
    end
  
    def sa(offset)
      read_i32(@f_sa, offset)
    end    
    
    def sa_block(offset, size)
      @f_sa.seek(offset * 4)
      b = @f_sa.read(4 * size)
      b.unpack('V*')
    end
    
    def sa_rel_path(sa_unit)
      relative_path = case sa_unit
      when 'juan'     then File.join(@option[:work], "%03d" % @option[:juan])
      when 'work'     then File.join(@option[:work])
      when 'canon'    then File.join(@option[:canon])
      when 'category' then File.join(@option[:category])
      when 'all'      then ''
      else
        abort "error: 錯誤的 sa_unit"
      end
      File.join(sa_unit, relative_path)
    end
    
    def search_sa(sa_path, q)
      return nil unless open_files(sa_path)
    
      i = bsearch(q, 0, @sa_last)
      return nil if i.nil?
    
      # 往前找符合的第一筆
      start = bsearch_start(q, 0, i)
    
      # 往後找符合的最後一筆
      stop = bsearch_stop(q, i, @sa_last)
    
      found = stop - start + 1
      @total_found += found      
      #@hits += result_hash(q, start, found)
      return sa_path, start, found
    end
    
    def search_sa_according_to_option(q)
      sa_results = []
      if @option.key? :works
        works = @option[:works].split(',')
        works.each do |w|
          @option[:work] = w
          sa_path = sa_rel_path('work')
          r = search_sa(sa_path, q)
          sa_results << r unless r.nil?
        end
      else
        if @option.key? :juan # 如果有指定卷號
          @juan = "%03d" % @option[:juan]
          sa_path = sa_rel_path('juan')
        elsif @option.key? :work
          sa_path = sa_rel_path('work')
        elsif @option.key? :canon
          sa_path = sa_rel_path('canon')
        elsif @option.key? :category
          sa_path = sa_rel_path('category')
        else
          sa_path = sa_rel_path('all')
        end
        index_folder = File.join(@sa_base, sa_path)
        if Dir.exist? index_folder
          r = search_sa(sa_path, q)
          sa_results << r unless r.nil?
        end
      end
      sa_results
    end
    
    def sort_word_count(q, sa_results)
      @next_word_count = {}
      @prev_word_count = {}
      
      sa_results.each do |sa_path, start, rows|
        open_files(sa_path)
        (0...rows).each do |i|
          j = sa(start+i)
          k = j<5 ? 0 : j-5
          s = read_str(k, 10+q.size) # 前後各取5個字
          s.gsub!("\n", '　')
        
          update_word_count(q, s)
        end
      end
      
      @prev_word_count = @prev_word_count.to_a
      @next_word_count = @next_word_count.to_a
      
      @prev_word_count.sort! { |x,y| y[1] <=> x[1] }
      @next_word_count.sort! { |x,y| y[1] <=> x[1] }
    end
    
    def suffix(rank, size)
      i = sa(rank)
      read_chars(i, size)
    end
  
    #def suffix_info(offset)
    #  puts "suffix_info, offset: #{offset}"
    #  i = offset
    #  @f_info.seek (i * SuffixInfo::SIZE)
    #  b = @f_info.read(SuffixInfo::SIZE)
    #  r = SuffixInfo::unpack(b)
    #  r['lb'] = "%04d%s%02d" % [r['page'], r['col'], r['line']]
    #  r.delete 'page'
    #  r.delete 'col'
    #  r.delete 'line'
    #  r
    #end
    
    def update_word_count(q, s)
      s.match /(.)?#{q}(.)?/ do
        unless $1.nil?
          if @prev_word_count.key? $1
            @prev_word_count[$1] += 1
          else
            @prev_word_count[$1] = 1
          end
        end
        unless $2.nil?
          if @next_word_count.key? $2
            @next_word_count[$2] += 1
          else
            @next_word_count[$2] = 1
          end
        end
      end
    end
  end
  
  class SuffixInfo
    SIZE = 22

    # vol,      a5, 5 bytes
    # work,     a7, 7 bytes
    # juan,     n,  2 bytes
    # offset,   N,  4 bytes, 32-bit unsigned, network (big-endian) byte order
    # page,     n,  2 bytes
    # col,      a,  1 byte
    # line,     C,  1 byte
    PATTERN = "a5a7nNnaC"

    def self.unpack(data)
      a = data.unpack PATTERN
      {
        'vol'    => a[0].strip,
        'work'   => a[1].strip,
        'juan'   => a[2],
        'offset' => a[3],
        'page'   => a[4],
        'col'    => a[5],
        'line'   => a[6]
      }
    end
    
    def self.unpack_to_a(data)
      a = data.unpack PATTERN
      a[0].strip!
      a[1].strip!
      return a
    end

    def initialize(opts={})
      @data = opts
      if @data[:lb].match(/^lb(\d+)([a-z])(\d+)$/)
        @data[:page] = $1.to_i
        @data[:col] = $2
        @data[:line] = $3.to_i
      else
        abort "lb format error: #{@data[:lb]}"
      end
    end

    def pack
      a = [
        @data[:vol],
        @data[:work],
        @data[:juan],
        @data[:offset],
        @data[:page],
        @data[:col],
        @data[:line]
      ]
      begin
        a.pack PATTERN
      rescue
        pp @data
        abort "suffix info pack error"
      end
    end
  end  
end