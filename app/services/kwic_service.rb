require 'action_view'
require 'fileutils'
require 'json'
require 'pp'

# search
#   search_sa_according_to_option
#     sa_rel_path
#     search_sa
#   #exclude_filter
#   sort_word_count
#   paginate
#     result_hash
#       sa_block
#       read_info_block
#       read_text_for_info_array
# search_juan
#   search_sa_juan
#   result_hash
# search_near
#   check_near
#     open_files
#     sort_by_pos
#     read_text_near
#       read_str

class KwicService
  attr_reader :config, :size, :text

  PUNCS = "\n.()[]-　．。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—"
  ABRIDGE = 15 # 夾注字數超過此設定，會被節略

  OPTION = {
    sort: 'f', # 預設按 keyword 之後的字排序
    edition: 'CBETA', # 預設搜尋 CBETA 版
    rows: 10,
    start: 0,
    around: 5, # 預設顯示關鍵字的前後五個字
    place: false,
    word_count: 0,
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
    @current_sa_path = nil
    @cache = Rails.configuration.x.v
    @sa_files = {}
    @text_files = {}
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
    @option = OPTION.merge args

    if @option[:sort] == 'b'
      q = query.reverse
    else
      q = query
    end
    
    @total_found = 0
    sa_results = search_sa_according_to_option(q)
    sort_word_count(q, sa_results) if @option[:word_count] > 0

    # 根據每頁筆數，只回傳一頁資料
    hits = paginate(q, sa_results)
    
    result = { 
      num_found: @total_found
    }

    if @option[:word_count] > 0
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
    
    result[:time] = Time.now - t1
    result[:results] = hits
    result
  end

  def search_juan(query, args={})
    @option = OPTION.merge args
    puts "search_juan, #{args.inspect}"
    
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
      start, found = search_sa_juan(sa_path, q)
      next if start.nil?
      hits += result_hash(q, start, found)
    end
    hits.sort_by! { |x| x['offset_in_text_with_punc'] }
  
    { 
      num_found: @total_found,
      results: hits
    }
  end

  def search_near(query, args={})
    t1 = Time.now
    @option = OPTION.merge args
    
    @total_found = 0

    unless @option.key? :juan
      raise CbetaError.new(400), "KWIC near 必須指定 juan 參數"
    end

    hits = search_near_juan(query, args)

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

  def bsearch_juan(q, left, right)
    return nil if left > right
    middle = (right - left) / 2 + left
    i = @f_sa[middle] # suffix offset
    s = @f_txt[i, q.size]
    if s == q
      return middle
    elsif middle == left
      return nil if s > q
      return bsearch_juan(q, middle+1, right)
    else
      if s > q
        return bsearch_juan(q, left, middle)
      else
        return bsearch_juan(q, middle, right)
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
  
  # 在 sa 中搜尋符合 q 的第一筆
  def bsearch_start_juan(q, left, right)
    return right if left >= right
    middle = (right - left) / 2 + left
    i = @f_sa[middle] # suffix offset
    s = @f_txt[i, q.size]
    if s == q
      return 0 if middle == 0
      i = @f_sa[middle-1] # suffix offset
      s = @f_txt[i, q.size]
      if s == q
        return bsearch_start_juan(q, left, middle-1)
      else
        return middle
      end
    else
      i = @f_sa[middle+1] # suffix offset
      s = @f_txt[i, q.size]
      if s == q
        return middle+1
      else
        return bsearch_start_juan(q, middle+1, right)
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

  # 在 sa 中搜尋符合 q 的最後一筆
  def bsearch_stop_juan(q, left, right)
    return left if left >= right
    middle = (right - left) / 2 + left
    i = @f_sa[middle] # suffix offset
    s = @f_txt[i, q.size]
    if s == q
      return middle if middle == @sa_last
      i = @f_sa[middle+1] # suffix offset
      s = @f_txt[i, q.size]
      if s == q
        return bsearch_stop_juan(q, middle+1, right)
      else
        return middle
      end
    else
      return left if middle == 0
      i = @f_sa[middle-1] # suffix offset
      s = @f_txt[i, q.size]
      if s == q
        return middle-1
      else
        return bsearch_stop_juan(q, left, middle-1)
      end
    end
  end

  def check_near(eligibles, near, q2, pos2)
    q1 = eligibles[:terms].last
    pos1 = eligibles[:pos_group]
    rows = []
    i1 = 0
    i2 = 0
    while (i1 < pos1.size) and (i2 < pos2.size)
      p1, sa1 = pos1[i1].last
      p2, sa2 = pos2[i2]

      if p1 > p2
        j = i1
        while (pos1[j][-1][0] - p2 - q2.size) <= near
          a = pos1[j].dup
          rows << (a << pos2[i2])
          j += 1
          break if j >= pos1.size
        end
        i2 += 1
      else
        j = i2
        while (pos2[j][0] - p1 - q1.size) <= near
          a = pos1[i1].dup
          rows << (a << pos2[j])
          j += 1
          break if j >= pos2.size
        end
        i1 += 1
      end
    end

    rows.sort_by! { |x| x.last }
    eligibles[:terms] << q2
    eligibles[:pos_group] = rows
  end

  def exclude_filter(sa_results, q)
    s1 = @option[:negative_lookbehind] 
    s2 = @option[:negative_lookahead]  
    
    return sa_results if s1.nil? and s2.nil?

    Rails.logger.warn "exclude_filter, q: #{q}"
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

  def exclude_filter2(info_array, q)
    # 前面不要出現的字
    if @option.key?(:negative_lookbehind)
      exclude_prefix(info_array, q, @option[:negative_lookbehind])
    end

    # 後面不要出現的字
    if @option.key?(:negative_lookahead)
      exclude_suffix(info_array, q, @option[:negative_lookahead])
    end
  end

  def exclude_prefix(info_array, q, prefix)
    q2 = prefix + q
    start, found = search_sa_after_open_files(q2)
    return if start.nil?

    #sa_array = sa_block(start, found)

    len = prefix.size
    a = []
    found.times do |i|
      a << (sa(start+i) + len)
    end

    info_array.delete_if { |x| a.include?(x[:sa_offset]) }
  end

  def exclude_suffix(info_array, q, suffix)
    q2 = q + suffix
    start, found = search_sa_after_open_files(q2)
    return if start.nil?

    sa_array = sa_block(start, found)

    info_array.delete_if { |x| sa_array.include?(x[:sa_offset]) }
  end

  def cache_fetch_juan_text(vol, work, juan)
    canon = CBETA.get_canon_from_vol(vol)
    # 換季要使用不同的 key
    key = "#{@cache}/text-with-punc/#{canon}/#{work}/#{juan}"
    Rails.cache.fetch(key) do
      fn = "%03d.txt" % juan
      fn = File.join(@txt_folder, canon, work, fn)
      # 待確認：L1557, 卷34 跨冊 有沒有問題
      File.binread(fn) 
    end
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
    return true if @current_sa_path == sa_path
    @current_sa_path = sa_path
    open_text(sa_path)
    open_sa   sa_path
    open_info sa_path
    true
  end

  def open_info(sa_path)
    if @option[:sort] == 'b' and not @option.key?(:juan)
      fn = abs_sa_path sa_path, 'info-b.dat'
    else
      fn = abs_sa_path sa_path, 'info.dat'
    end
    
    begin
      @f_info = File.open(fn, 'rb')
    rescue
      raise CbetaError.new(500), "開檔失敗: #{fn}"
    end
  end
  
  def open_sa(sa_path)
    if @option[:sort] == 'b'
      fn = abs_sa_path sa_path, 'sa-b.dat'
    else
      fn = abs_sa_path sa_path, 'sa.dat'
    end

    if @option.key?(:juan)
      k = "#{@cache}/sa/#{@option[:work]}/#{@option[:juan]}/#{@option[:sort]}"
      @f_sa = Rails.cache.fetch(k) do
        File.read(fn, mode: "rb").unpack("V*")
      end
      return unless @f_sa.nil?
    end

    if @sa_files.key?(fn)
      @f_sa = @sa_files[fn]
      return
    end
    
    begin
      Rails.logger.warn "open sa from file: #{fn}"
      @f_sa = File.open(fn, 'rb')
      @sa_files[fn] = @f_sa
    rescue
      raise CbetaError.new(500), "開檔失敗: #{fn}"
    end
  end

  def open_text(sa_path)
    if @option[:sort] =='b'
      fn = abs_sa_path sa_path, 'all-b.txt'
    else
      fn = abs_sa_path sa_path, 'all.txt'
    end

    if @option.key?(:juan)
      k = "#{@cache}/text/#{@option[:work]}/#{@option[:juan]}/#{@option[:sort]}"
      @f_txt = Rails.cache.fetch(k) do
        File.read(fn, encoding: "UTF-32LE")
      end
      unless @f_txt.nil?
        @sa_last = @f_txt.size - 1 # sa 最後一筆的 offset
        @size = @f_txt.size
        return
      end
    end

    if @text_files.key?(fn)
      h = @text_files[fn]
      @f_txt   = h[:file_handle]
      @size    = h[:size]
      @sa_last = h[:sa_last]
      return
    end

    begin
      Rails.logger.warn "open text from file: #{fn}"
      @f_txt = File.open(fn, 'rb')
      @size = @f_txt.size / 4
      @sa_last = @size - 1 # sa 最後一筆的 offset
      @text_files[fn] = {
        file_handle: @f_txt,
        size: @size,
        sa_last: @sa_last
      }
    rescue
      raise CbetaError.new(500), "開檔失敗: #{fn}"
    end

    true
  end
  
  def paginate(q, sa_results)
    Rails.logger.warn "paginate, q: #{q}"
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
    hits = []
    sa_results.each do |sa_path, start, found|
      hits += result_hash(q, start, found)
    end
    hits.sort_by! { |x| x['offset_in_text_with_punc'] }
    hits[@option[:start], @option[:rows]]
  end

  def read_i32(fi, offset)
    if @f_sa.kind_of?(Array)
      #Rails.logger.warn "read sa from ram"
      @f_sa[offset]
    else
      #Rails.logger.warn "read sa from file"
      fi.seek (offset * 4)
      b = fi.read(4)
      b.unpack('V')[0]
    end
  end

  def read_info_block(q, offset, size)
    return read_info_block_juan(q, offset, size) if @option.key?(:juan)

    @f_info.seek (offset * SuffixInfo::SIZE)
    block = @f_info.read(SuffixInfo::SIZE * size)
    r = []
    (0...size).each do |i|
      j = i * SuffixInfo::SIZE
      b = block[j, SuffixInfo::SIZE]
      h = SuffixInfo::unpack(b)
      h['lb'] = "%s%s%02d" % [h['page'], h['col'], h['line']]
      h.delete 'page'
      h.delete 'col'
      h.delete 'line'
      h[:sa_offset] = sa(offset + i)
      r << h
    end
    r
  end

  # 單卷 info 檔的順序是依原 text 順序
  def read_info_block_juan(q, offset, size)
    debug "[#{__LINE__}] size: #{@size}"
    r = []
    (0...size).each do |i|
      sa_offset = offset + i
      text_offset = sa(sa_offset)
      if @option[:sort] == 'b'
        text_offset = @size - text_offset - 1
      end
      Rails.logger.debug "read_info_block_juan, text_offset: #{text_offset}"

      h = suffix_info(text_offset)
      h[:sa_offset] = sa_offset

      # 記錄 keyword 在「含標點、校注 全文」裡的結束位置
      if @option[:sort] == 'b'
        text_offset -= (q.size - 1)
      else
        text_offset += q.size - 1
      end
      Rails.logger.debug "read_info_block_juan, text_offset: #{text_offset}"
      h2 = suffix_info(text_offset)
      h['offset2'] = h2['offset_in_text_with_punc']

      r << h
    end
    r
  end

  def read_str(offset, length)
    if @f_txt.kind_of?(String)
      @f_txt[offset, length]
    else
      #Rails.logger.warn "read_str from file"
      @f_txt.seek (offset * 4)
      b = @f_txt.read(length * 4)
      raise "讀取 text 檔錯誤, file size: #{@size}, offset: #{offset}" if b.nil?
      @encoding_converter.convert(b)
    end
  end
  
  def read_str_with_punc(text, offset, length)
    b = text[offset * 4, length * 4]
    return '' if b.nil?
    @encoding_converter.convert(b)
  end

  def read_text_for_info_array(info_array, q)
    t1 = Time.now
    if @option[:kwic_w_punc] or @option[:kwic_wo_punc]
      if @option[:kwic_wo_punc]
        info_array.each do |data|      
          data['kwic_no_punc'] = read_text_wo_punc(data[:sa_offset], q)
        end
      end

      if @option[:kwic_w_punc]
        info_array.each do |data|
          if @option.key?(:juan) # 單卷才提供含標點的 kwic
            data['kwic'] = read_text_with_punc(data, q)
          elsif @option[:kwic_wo_punc]
            data['kwic'] = data['kwic_no_punc']
          else
            data['kwic'] = read_text_wo_punc(data[:sa_offset], q)
          end
        end
      end
    end
    
    info_array.each do |h|
      h.delete :sa_offset
      h.delete 'offset2'
    end
  end

  def read_text_near(matches)
    m1 = matches.first
    debug "[#{__LINE__}] m1: #{m1.inspect}"
    offset_wo_punc = m1[:pos_sa][0]
    debug "[#{__LINE__}] offset_in_text_wo_punc: #{offset_wo_punc}"

    q1 = m1[:term]

    info = suffix_info(offset_wo_punc)
    text = cache_fetch_juan_text(info['vol'], info['work'], info['juan'])
    p1 = info['offset_in_text_with_punc']
    debug "[#{__LINE__}] p1: #{p1}"

    if p1 < @option[:around]
      r = read_str_with_punc(text, 0, p1)
    else
      start = p1 - @option[:around]
      r = read_str_with_punc(text, start, @option[:around])
    end

    r += "<mark>"
    offset2 = offset_wo_punc + q1.size - 1
    p2 = get_t2_offset_by_t1_offset(offset2)
    size = p2 - p1 + 1
    r += read_str_with_punc(text, p1, size)
    r += "</mark>"

    found = false
    prev_p2 = p2
    matches[1..-1].each do |m|
      debug "prev_p2: #{prev_p2}"
      q2 = m[:term]
      debug "[#{__LINE__}] q2: #{q2}"
      offset1 = m[:pos_sa][0]
      debug "[#{__LINE__}] offset1: #{offset1}"
      offset2 = offset1 + q2.size - 1
      p2 = get_t2_offset_by_t1_offset(offset2)
      debug "p2: #{p2}"
      if p2 <= prev_p2 # 與上一個詞完全重疊
        debug "與上一個詞完全重疊"
        next 
      end
      
      p1 = get_t2_offset_by_t1_offset(offset1)
      size = p1 - prev_p2 - 1
      s = read_str_with_punc(text, prev_p2+1, size)
      r += abridge_note(s)
  
      r += "<mark>"
      size = p2 - p1 + 1
      r += read_str_with_punc(text, p1, size)
      r += "</mark>"

      prev_p2 = p2
      found = true
    end

    return nil unless found

    r + read_str_with_punc(text, p2+1, @option[:around])
  end
  
  # t1_offset: 不含標點
  # t2_offset: 含標點
  def get_t2_offset_by_t1_offset(offset)
    info = suffix_info(offset)
    info['offset_in_text_with_punc']
  end

  def read_text_with_punc(data, q)
    return nil unless @option.key?(:juan)

    text = cache_fetch_juan_text(data['vol'], data['work'], data['juan'])
    
    r = ''
    position = nil

    # 如果 sort=b, offset 指向 q 的最後一個字，要先將 pointer 移至 q 的第一個字
    if @option[:sort] == 'b'
      start_position = data['offset2']
      stop_position  = data['offset_in_text_with_punc']
    else
      start_position = data['offset_in_text_with_punc']
      stop_position  = data['offset2']
    end
    
    # 讀 關鍵字 前面的字
    if start_position < @option[:around]
      length = start_position * 4
      b = text[0, length]
    else
      length = @option[:around] * 4
      start = start_position * 4 - length
      b = text[start, length]
    end
    r += @encoding_converter.convert(b)

    # 讀 關鍵字 (可能夾雜標點、夾注)
    r += '<mark>' if @option[:mark]
    start = start_position * 4
    length = (stop_position - start_position + 1) * 4
    b = text[start, length]
    c = @encoding_converter.convert(b)
    r += abridge_note(c)
    r += '</mark>' if @option[:mark]
    
    # 讀 關鍵字 之後的字
    start = (stop_position + 1) * 4
    len = @option[:around] * 4
    b = text[start, len]
    r += @encoding_converter.convert(b) unless b.nil?      
    r
  end

  def abridge_note(str)
    str.gsub(/\((.*?)\)/) do |s|
      if s.size > ABRIDGE
        s = $1
        s = s[0,2] + "⋯中略#{s.size-4}字⋯" + s[-2..-1]
        "(#{s})"
      else
        $&
      end
    end
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
    return [] if rows == 0
    return [] if start.nil?
    info_array = read_info_block(q, start, rows)
    
    if @option.key?(:juan)
      if @option.key?(:negative_lookbehind) or @option.key?(:negative_lookahead)
        t1 = Time.now
        exclude_filter2(info_array, q)
      end
    end

    read_text_for_info_array(info_array, q)
    add_place_info(info_array) if @option[:place] # 附上 地理資訊
    info_array
  end

  def sa(offset)
    read_i32(@f_sa, offset)
  end
  
  def sa_block(offset, size)
    if @f_sa.kind_of?(Array)
      @f_sa[offset, size]
    else
      @f_sa.seek(offset * 4)
      b = @f_sa.read(4 * size)
      b.unpack('V*')
    end
  end

  def sa_paths_by_option
    if @option.key? :works
      works = @option[:works].split(',').uniq
      r = []
      works.each do |w|
        @option[:work] = w
        r << sa_rel_path('work')
      end
      return r
    end

    if @option.key? :canon
      canons = @option[:canon].split(',').uniq
      r = []
      canons.each do |c|
        @option[:canon] = c
        r << sa_rel_path('canon')
      end
      return r
    end

    return [sa_rel_path('juan')] if @option.key? :juan # 如果有指定卷號
    return [sa_rel_path('work')] if @option.key? :work
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

  # 單卷範圍內 做 NEAR 搜尋
  def search_near_juan(query, args={})
    Rails.logger.warn "search_near_juan, query: #{query}"
    sa_path = sa_rel_path('juan')
    return nil unless open_files(sa_path)

    if query.match(/^"(\S+)" (NEAR\/(\d+) .*)$/)
      q1 = $1
      nears = $2
      start1, found1 = search_sa_after_open_files(q1)
      return [] if start1.nil?

      pos1 = sort_by_pos(start1, found1)
      eligibles = {
        terms: [q1],
        pos_group: pos1.map { |x| [x] }
      }

      nears.scan(/NEAR\/(\d+) "(\S+)"/).each do |near, q|
        start2, found2 = search_sa_after_open_files(q)
        pos2 = sort_by_pos(start2, found2)
        check_near(eligibles, near.to_i, q, pos2)
      end
    else
      raise CbetaError.new(400), "NEAR 語法錯誤 query: #{query}"
    end

    hits = []
    eligibles[:pos_group].each do |pos_group|
      a = []
      pos_group.each_with_index do |v, i|
        a << { 
          pos_sa: v,
          term: eligibles[:terms][i]
        }
      end
      a.sort_by! { |x| x[:pos_sa].first }
      kwic = read_text_near(a)
      unless kwic.nil?
        offset_wo_punc = a[0][:pos_sa][0]
        info = suffix_info(offset_wo_punc)
        info['kwic'] = kwic
        hits << info
      end
    end
    hits
  end
  
  def search_sa(sa_path, q)
    Rails.logger.warn "search_sa, q: #{q}"
    return nil unless open_files(sa_path)
    search_sa_after_open_files(q)
  end

  def search_sa_juan(sa_path, q)
    Rails.logger.warn "search_sa_juan, q: #{q}"
    return nil unless open_files(sa_path)
    search_sa_after_open_files_juan(q)
  end

  def search_sa_after_open_files(q)
    t1 = Time.now
    i = bsearch(q, 0, @sa_last)
    return nil if i.nil?
  
    # 往前找符合的第一筆
    start = bsearch_start(q, 0, i)
  
    # 往後找符合的最後一筆
    stop = bsearch_stop(q, i, @sa_last)
  
    found = stop - start + 1
    @total_found += found
    #debug "search_sa_after_open_files, q: #{q}, 花費時間: #{Time.now - t1}"
    return start, found
  end
  
  def search_sa_after_open_files_juan(q)
    t1 = Time.now
    i = bsearch_juan(q, 0, @sa_last)
    return nil if i.nil?
  
    # 往前找符合的第一筆
    start = bsearch_start_juan(q, 0, i)
  
    # 往後找符合的最後一筆
    stop = bsearch_stop_juan(q, i, @sa_last)
  
    found = stop - start + 1
    @total_found += found
    #debug "search_sa_after_open_files, q: #{q}, 花費時間: #{Time.now - t1}"
    return start, found
  end

  def search_sa_according_to_option(q)
    sa_results = []
    sa_paths_by_option.each do |sa_path|
      start, found = search_sa(sa_path, q)
      sa_results << [sa_path, start, found] unless start.nil?
    end
    sa_results
  end

  def sort_by_pos(start, size)
    abort "#{__LINE__} start is nil" if start.nil?
    # 創建 820722 個元素，花費 1.7 秒
    a = Array.new(size) { |i| [sa(start + i), start + i] }
    a.sort
  end

  def sort_word_count(q, sa_results)
    Rails.logger.warn "sort_word_count: #{q}"
    @next_word_count = Hash.new(0)
    @prev_word_count = Hash.new(0)
    
    wc = @option[:word_count].to_i
    sa_results.each do |sa_path, start, rows|
      next unless open_files(sa_path)
      (0...rows).each do |i|
        j = sa(start+i)
        k = j<5 ? 0 : j-5
        s = read_str(k, 10+q.size) # 前後各取5個字
        s.gsub!("\n", '　')
      
        s.match /(.{#{wc}})?#{q}(.{#{wc}})?/ do
          @prev_word_count[$1] += 1 unless $1.nil?
          @next_word_count[$2] += 1 unless $2.nil?
        end    
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
    r['lb'] = "%s%s%02d" % [r['page'], r['col'], r['line']]
    r.delete 'page'
    r.delete 'col'
    r.delete 'line'
    r
  end
  
  include ApplicationHelper

end # end of class SearchEngine
