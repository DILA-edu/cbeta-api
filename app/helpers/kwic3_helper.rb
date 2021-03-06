require 'action_view'
require 'fileutils'
require 'json'
require 'pp'

# search
#   search_sa_according_to_option
#     sa_rel_path
#     search_sa
#   exclude_filter
#   sort_word_count
#   paginate
#     result_hash
#       sa_block
#       read_info_block
#       read_text_for_info_array
# search_near
#   check_near
#     open_files
#     sort_by_pos
#     read_text_near
#       read_str

module Kwic3Helper

  # 將數字轉為加上千位號的字串
  def n2c(n)
    ActionView::Base.new.number_to_currency(n, unit: '', precision: 0)
  end

  class SearchEngine
    attr_reader :config, :size, :text
  
    PUNCS = "\n.()[]-　．。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—"

    OPTION = {
      sort: 'f', # 預設按 keyword 之後的字排序
      edition: 'CBETA', # 預設搜尋 CBETA 版
      rows: 10,
      start: 0,
      around: 5, # 預設顯示關鍵字的前後五個字
      place: false,
      word_count: false,
      mark: false,
      kwic_w_punc: true, # 是否回傳含標點的文字
      kwic_wo_punc: false, # 是否回傳不含標點的文字
      seg: false # 是否自動分詞
    }
  
    # param @base [String] suffix array base folder
    def initialize(base)
      @sa_base    = File.join(base, 'sa')   # suffix array folder
      @txt_folder = File.join(base, 'text') # 含有標點的純文字檔
      @encoding_converter = Encoding::Converter.new("UTF-32LE", "UTF-8")
      #init_cache
      @text_with_puncs = {}
    end
    
    def abs_sa_path(sa_path, name)
      if sa_path.nil?
        Rails.logger.fatal "傳入 abs_sa_path 的 sa_path 參數是 nil, 程式：#{__FILE__}, 行號：#{__LINE__}"
        return nil
      end
      File.join(@sa_base, sa_path, name)
    end
  
    def search(query, args={})
      warn "#{__LINE__} begin kwic3 search, query: #{query}, args: " + args.inspect
      warn "#{__LINE__} OPTION: " + OPTION.inspect
      @option = OPTION.clone
      @option.merge! args
      warn "#{__LINE__} @option: " + @option.inspect
      
      if @option[:sort] == 'b'
        q = query.reverse
      else
        q = query
      end
      
      @total_found = 0
      sa_results = search_sa_according_to_option(q)
      warn "sa_results:\n" + sa_results.inspect
      
      sa_results = exclude_filter(sa_results, q)
      
      sort_word_count(q, sa_results) if @option[:word_count]

      # 根據每頁筆數，只回傳一頁資料
      hits = paginate(q, sa_results)
      
      result = { 
        num_found: @total_found
      }

      if @option[:word_count]
        result[:prev_word_count] = @prev_word_count
        result[:next_word_count] = @next_word_count
      end

      if @option[:seg]
        hits.each do |h|
          r = WordSegService.new.run(h['kwic'])
          if r.success?
            h['seg'] = r.result
          else
            h['seg'] = r.errors
          end
        end
      end
      
      result[:results] = hits
      warn "#{__LINE__} end kwic3 search, query: #{query}, args: " + args.inspect
      result
    end
  
    def search_juan(query, args={})
      @option = OPTION.clone
      @option.merge! args
      
      if @option[:sort] == 'b'
        keywords = query.reverse
      else
        keywords = query
      end
      
      @total_found = 0
      @juan = "%03d" % @option[:juan]
      sa_path = sa_rel_path('juan')
      hits = []
      keywords.split(',').each do |q| # 可能有多個關鍵字
        sa_path, start, found = search_sa(sa_path, q)
        hits += result_hash(q, start, found)
      end
      pp hits
      hits.sort_by! { |x| x['offset'] }
    
      { 
        num_found: @total_found,
        results: hits
      }
    end

    def search_near(q1, q2, near, args={})
      Rails.logger.debug "#{__LINE__} #{Time.now}"
      t1 = Time.now
      @option = OPTION.merge! args
      
      @total_found = 0
      hits = []

      sa_paths_by_option.each do |sa_path|
        Rails.logger.debug "#{__LINE__} sa_path: #{sa_path}"
        a1 = search_sa(sa_path, q1)
        next if a1.nil?
        a2 = search_sa(sa_path, q2)
        next if a2.nil?
        hits += check_near(near, q1, a1, q2, a2)
      end

      { 
        num_found: hits.size,
        time: Time.now - t1,
        results: hits
      }
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

    def check_near(near, q1, a1, q2, a2)
      Rails.logger.debug "#{__LINE__} #{Time.now} 開始 check_near"
      sa_path1, start1, found1 = a1
      sa_path2, start2, found2 = a2

      open_files(sa_path1)

      Rails.logger.debug "#{__LINE__} #{Time.now} 依位置排序"
      pos1 = sort_by_pos(start1, found1)
      pos2 = sort_by_pos(start2, found2)

      rows = []
      i1 = 0
      i2 = 0
      t1 = Time.now
      while (i1 < pos1.size) and (i2 < pos2.size)
        p1, sa1 = pos1[i1]
        p2, sa2 = pos2[i2]

        if p1 > p2
          j = i1
          while (pos1[j][0] - p2 - q2.size) <= near
            rows << [p2, pos1[j][0], q2, q1, suffix_info(sa2)]
            j += 1
            break if j >= pos1.size
          end
          i2 += 1
        else
          j = i2
          while (pos2[j][0] - p1 - q1.size) <= near
            rows << [p1, pos2[j][0], q1, q2, suffix_info(sa1)]
            j += 1
            break if j >= pos2.size
          end
          i1 += 1
        end
      end
      Rails.logger.debug "#{__LINE__} 兩兩比對距離 花費時間：#{Time.now - t1}"

      t1 = Time.now
      hits = []
      rows.each do |p3, p4, q3, q4, info|
        info['kwic'] = read_text_near(p3, p4, q3, q4)
        hits << info
      end
      Rails.logger.debug "#{__LINE__} 讀取文字 花費時間：#{Time.now - t1}"

      t1 = Time.now
      hits.sort_by! { |h| h['vol'] + h['lb'] }
      Rails.logger.debug "#{__LINE__} 依 vol+lb 排序  花費時間：#{Time.now - t1}"
      hits
    end

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
        next unless open_files(sa_path)
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

    def cache_fetch_juan_text(vol, work, juan)
      # 不使用 cache
      # # 換季要使用不同的 key
      # key = Rails.application.config.sphinx_index + "kwic-text-#{vol}-#{work}-#{juan}"
      # Rails.cache.fetch(key) do
      #   fn = "%03d.txt" % juan
      #   fn = File.join(@txt_folder, vol, work, fn)
      #   # 待確認：L1557, 卷34 跨冊 有沒有問題
      #   File.binread(fn) 
      # end
      fn = "%03d.txt" % juan
      fn = File.join(@txt_folder, vol, work, fn)
      # 待確認：L1557, 卷34 跨冊 有沒有問題
      File.binread(fn) 
    end
    
    def debug(s)
      Rails.logger.debug s
    end
  
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
      warn "#{__LINE__} open_files: #{sa_path}"
      open_text(sa_path)
      open_sa   sa_path
      open_info sa_path
      true
    end
  
    def open_info(sa_path)
      if @option[:sort] == 'b'
        fn = abs_sa_path sa_path, 'info-b.dat'
      else
        fn = abs_sa_path sa_path, 'info.dat'
      end
      raise CbetaError.new(500), "檔案不存在: #{fn}" unless File.exist?(fn)
      @f_info = File.open(fn, 'rb')
    end
    
    def open_sa(sa_path)
      warn "#{__LINE__} open_sa: sa_path: #{sa_path}"
      if @option[:sort] == 'b'
        fn = abs_sa_path sa_path, 'sa-b.dat'
      else
        fn = abs_sa_path sa_path, 'sa.dat'
      end
      warn "open suffix array file: #{fn}"
      raise CbetaError.new(500), "檔案不存在: #{fn}" unless File.exist?(fn)
      @f_sa = File.open(fn, 'rb')
    end
  
    def open_text(sa_path)
      if @option[:sort] =='b'
        fn = abs_sa_path sa_path, 'all-b.txt'
      else
        fn = abs_sa_path sa_path, 'all.txt'
      end
      raise CbetaError.new(500), "檔案不存在: #{fn}" unless File.exist? fn
      
      @f_txt = File.open(fn, 'rb')
      @size = @f_txt.size / 4
      @sa_last = @size - 1 # sa 最後一筆的 offset
      true
    end
    
    def paginate(q, sa_results)
      if @option.key?(:juan) and @option[:sort]=='location'
        return paginate_by_location(q, sa_results)
      end

      page_start = @option[:start]
      rows = @option[:rows]
      hits = []
      sa_results.each do |sa_path, start, found|
        unless page_start == 0
          if found > page_start
            start += page_start
            found -= page_start
            page_start = 0
          else
            page_start -= found
            next
          end
        end
        
        next unless open_files(sa_path)
        if rows > found
          hits += result_hash(q, start, found)
          rows -= found
        else
          hits += result_hash(q, start, rows)
          break
        end
      end
      hits
    end

    def paginate_by_location(q, sa_results)
      Rails.logger.debug "paginate_by_location"
      hits = []
      sa_results.each do |sa_path, start, found|
        hits += result_hash(q, start, found)
      end
      hits.sort_by! { |x| x['offset'] }
      hits[@option[:start], @option[:rows]]
    end

    def read_i32(fi, offset)
      fi.seek (offset * 4)
      b = fi.read(4)
      b.unpack('V')[0]
    end

    def read_info_block(sa_array, offset, size)
      Rails.logger.debug "read_info_block, offset: #{offset}"
      @f_info.seek (offset * SuffixInfo::SIZE)
      block = @f_info.read(SuffixInfo::SIZE * size)
      r = []
      (0...size).each do |i|
        j = i * SuffixInfo::SIZE
        b = block[j, SuffixInfo::SIZE]
        h = SuffixInfo::unpack(b)
        h['lb'] = "%04d%s%02d" % [h['page'], h['col'], h['line']]
        h.delete 'page'
        h.delete 'col'
        h.delete 'line'
        h[:sa_offset] = sa_array[i]
        r << h
      end
      r
    end
  
    def read_str(offset, length)
      @f_txt.seek (offset * 4)
      b = @f_txt.read(length * 4)
      raise "讀取 text 檔錯誤, file size: #{@size}, offset: #{offset}" if b.nil?
      @encoding_converter.convert(b)
    end
    
    def read_text_for_info_array(info_array, q)
      Rails.logger.debug "read_text_for_info_array, q: #{q}"
      t1 = Time.now
      if @option[:kwic_w_punc] or @option[:kwic_wo_punc]
        if @option[:kwic_w_punc]
          info_array.each do |data|
            data['kwic'] = read_text_with_punc(data, q)
          end
        end
      
        if @option[:kwic_wo_punc]
          info_array.each do |data|      
            data['kwic_no_punc'] = read_text_wo_punc(data[:sa_offset], q)
          end
        end
      end
      
      info_array.each do |h|
        h.delete :sa_offset
      end
    end

    def read_text_near(p1, p2, q1, q2)
      if p1 < @option[:around]
        i1 = 0
        r = read_str(0, p1)
      else
        i1 = p1 - @option[:around]
        r = read_str(i1, @option[:around])
      end

      r += "<mark>#{q1}</mark>"
      i1 = p1 + q1.size

      r += read_str(i1, p2-i1)

      r += "<mark>#{q2}</mark>"
      i1 = p2 + q2.size

      r + read_str(i1, @option[:around])
    end
    
    def read_text_with_punc(data, q)
      key = "#{data['vol']}-#{data['work']}-#{data['juan']}"
      unless @text_with_puncs.key? key
        @text_with_puncs[key] = cache_fetch_juan_text(data['vol'], data['work'], data['juan'])
      end
      text = @text_with_puncs[key]
      
      r = ''
      position = nil
      i = data['offset']

      # 如果 sort=b, offset 指向 q 的最後一個字，要先將 pointer 移至 q 的第一個字
      if @option[:sort] == 'b'
        position = i * 4
        j = q.size
        while j > 1
          c = @encoding_converter.convert(text[i * 4, 4])
          j -= 1 unless PUNCS.include? c
          i -= 1
        end
      end
      
      # 讀 關鍵字 前面的字
      if i < @option[:around]
        position = i * 4
        b = text[0, position]
      else
        start = (i - @option[:around]) * 4
        length = @option[:around] * 4
        b = text[start, length]
        position = start + length
      end
      
      r += @encoding_converter.convert(b)
      r += '<mark>' if @option[:mark]
      
      # 讀 關鍵字 (可能夾雜標點)
      len = q.size
      while (len > 0) and (position < text.size)
        b = text[position, 4]
        position += 4
        
        c = @encoding_converter.convert(b)
        r += c
        len -= 1 unless PUNCS.include? c
      end
      
      r += '</mark>' if @option[:mark]
      
      # 讀 關鍵字 之後的字
      len = @option[:around] * 4
      b = text[position, len]
      r += @encoding_converter.convert(b) unless b.nil?      
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
        text = k + s.reverse
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
        
    def result_hash(q, start, rows)
      Rails.logger.debug "result_hash, q: #{q}, start: #{start}"
      return [] if rows == 0
      
      sa_array = sa_block(start, rows)
      info_array = read_info_block(sa_array, start, rows)
      read_text_for_info_array(info_array, q)
      add_place_info(info_array) if @option[:place] # 附上 地理資訊
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

    def sa_paths_by_option
      debug "#{__LINE__} sa_paths_by_option: @option: " + @option.inspect
      if @option.key? :works
        works = @option[:works].split(',').uniq
        r = []
        works.each do |w|
          @option[:work] = w
          r << sa_rel_path('work')
        end
        return r
      end

      return [sa_rel_path('juan')] if @option.key? :juan # 如果有指定卷號
      return [sa_rel_path('work')] if @option.key? :work
      return [sa_rel_path('canon')] if @option.key? :canon
      return [sa_rel_path('category')] if @option.key? :category

      [sa_rel_path('all')]
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
      debug "#{__LINE__} search_sa, sa_path: #{sa_path}, q: #{q}"
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
      sa_paths_by_option.each do |sa_path|
        r = search_sa(sa_path, q)
        sa_results << r unless r.nil?
      end
      sa_results
    end

    def sort_by_pos(start, size)
      t1 = Time.now
      a = Array.new(size) { |i| [sa(start + i), start + i] }
      # 創建 820722 個元素，花費 1.7 秒
      Rails.logger.debug "#{__LINE__} sort_by_pos 創建矩陣 花費時間： #{Time.now - t1}, size: #{a.size}"
      t1 = Time.now
      a.sort!
      Rails.logger.debug "#{__LINE__} sort_by_pos sort 花費時間： #{Time.now - t1}"
      a
    end

    def sort_word_count(q, sa_results)
      @next_word_count = {}
      @prev_word_count = {}
      
      sa_results.each do |sa_path, start, rows|
        next unless open_files(sa_path)
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
  
    def suffix_info(offset)
      i = offset
      @f_info.seek (i * SuffixInfo::SIZE)
      b = @f_info.read(SuffixInfo::SIZE)
      r = SuffixInfo::unpack(b)
      r['lb'] = "%04d%s%02d" % [r['page'], r['col'], r['line']]
      r.delete 'page'
      r.delete 'col'
      r.delete 'line'
      r
    end
    
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

    def warn(s)
      Rails.logger.warn s
    end

  end # end of class SearchEngine
end # end of module