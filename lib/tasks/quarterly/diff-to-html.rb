require 'net/http'
require 'diff/lcs'
require 'cbeta'
require 'csv'

class DiffToHTML

  #API = 'http://cbdata.dila.edu.tw/v1.2'
  API = 'http://cbdata.dila.edu.tw/dev'
  PUNCS = '.()[] 。，、；？！：「」『』《》＜＞〈〉〔〕［］【】〖〗…—　'
  WORD = %r{
    \[[^\]]+\]|  # 組字式
    [a-zA-Z\u{D1}-\u{227}\u{1E04}-\u{1EE5}]+ # 英梵巴
    |.
  }x

  def initialize(config)
    @config = config
    @base = config[:change_log]
  end

  def convert
    @v1 = @config[:q1]
    @v2 = @config[:q2]

    @old_nor = "cbeta-normal-#{@v1}"
    @new_nor = "cbeta-normal-#{@v2}"

    fn = File.join(@base, 'diff-to-html-log.htm')
    @log = File.open(fn, 'w')
    @log.puts html_header
    @titles = read_titles

    p = Regexp.quote(PUNCS)
    @puncs_regexp = /[#{p}]/

    @juans_count = 0
    @lines_count = 0
    @added = ''
    @removed = ''

    src = File.join(@base, 'diff.txt')
    puts "read #{src}"
    diff_text = File.read(src)
    modified = parse_diff_text(diff_text)

    fn = File.join(@base, "#{@v2}.htm")
    puts "輸出檔：#{fn}"
    fo = File.open(fn, 'w')
    fo.puts html_header

    unless @removed.empty?
      fo.puts "<h2>移除</h2>\n"
      fo.puts "<ul>\n"
      fo.puts @removed
      fo.puts "</ul>"
    end

    unless @added.empty?
      fo.puts "<h2>新增</h2>\n"
      fo.puts "<ul>\n"
      fo.puts @added
      fo.puts "</ul>"
    end

    fo.puts "<h2>共變更 #{@juans_count} 卷，#{n2s(@lines_count)} 行</h2>"
    fo.puts modified

    fo.puts "</body></html>"
    @log.puts "</body></html>"
  end

  def add_canon(folder, canon)
    puts "add_canon: #{folder}, #{canon}"
    canon_folder = File.join(folder, canon)
    Dir.entries(canon_folder).sort.each do |vol|
      next if vol.end_with? '.'
      rel_path = File.join(folder, canon, vol)
      add_vol(rel_path)
    end  
  end

  def add_juan(folder, juan)
    puts "add_juan: #{folder}, juan: #{juan}"
    a = folder.split('/')
    work = a.last
    a.shift
    f = a.join('/')
    work_id = CBETA.get_work_id_from_file_basename(work)
    title = @titles[work_id]
    @added += "<li>#{f}/#{work}《#{title}》卷#{juan}</li>\n"
  end

  def add_vol(rel_path)
    puts "add_vol: #{rel_path}"
    path = File.join(@base, rel_path)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      add_work(rel_path, f)
    end
  end

  def add_work(folder, work)
    puts "add_work: #{folder}, #{work}"
    a = folder.split('/')
    a.shift
    f = a.join('/')
    work_id = CBETA.get_work_id_from_file_basename(work)
    title = @titles[work_id]
    @added += "<li>#{f}/#{work}《#{title}》</li>\n"
  end

  def diff_chars(from, to)
    @log.puts "<p>diff_chars</p>
  <ul>
  <li>#{from}</li>
  <li>#{to}</li>"
    if to.empty?
      r = ''
      from.split("\n").each do |s|
        #r += s.sub(/^(.*?║)(.*)$/, "\\1<del>\\2</del><br>\n")
        r += "<del>#{s}</del><br>\n"
      end
    elsif from.empty?
      r = ''
      to.split("\n").each do |s|
        #r += s.sub(/^(.*?║)(.*)$/, "\\1<del>\\2</del><br>\n")
        r += "<ins>#{s}</ins><br>\n"
      end
    else
      r = diff_lcs(from, to)
    end
    @log.puts "<li>#{r}</li></ul>"
    r
  end

  def diff_lcs(s1, s2)
    r = ''
    a1 = s2a(s1)
    a2 = s2a(s2)
    diffs = Diff::LCS.sdiff(a1, a2)
    diffs.each do |change|
      case change.action
      when '='
        r += change.old_element
      when '!'    # replace
        r += "<del>#{change.old_element}</del>"
        r += "<ins>#{change.new_element}</ins>"
      when '-'    # delete
        r += "<del>#{change.old_element}</del>"
      when '+'    # insert
        r += "<ins>#{change.new_element}</ins>"
      end
    end
    r
  end

  def diff_puncs(str1, str2)
    a1 = str1.chars
    a2 = str2.chars
    r = ''
    while !a2.empty? or !a1.empty?
      if a2.first == a1.first
        r += a2.shift
        a1.shift
      elsif !a2.empty? and PUNCS.include? a2.first
        r += '<ins>%s</ins>' % a2.shift
      elsif PUNCS.include? a1.first
        r += '<del>%s</del>' % a1.shift
      else
        abort "diff_puncs error"
      end
    end
    r
  end

  # 指定字型，5碼 Unicode 才能正確顯示
  # diff-to-html.rb 使用 <del>, <ins> 元素方便處理
  # change-log-font.rb 改為 <span class="del">, <span class="ins">
  # 如果使用 ins, del 標記，在 ms word 開啟會出現「追蹤修訂」左邊線
  def html_header
    %(<!DOCTYPE html>
  <html lang="zh-TW">
  <head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  <style type="text/css"> 
    body { 
      font-family: Helvetica, "Hanazono Mincho C Regular";
    }
    .hmc {
      font-family: "Hanazono Mincho C Regular";
    }
    del { 
      color: red;
      text-decoration: line-through;
    }
    .del { 
      color: red;
      text-decoration: line-through;
    }
    ins { 
      color: blue;
      font-weight: bold;
      text-decoration: none;
      background-color: yellow;
    }
    .ins { 
      color: blue;
      font-weight: bold;
      text-decoration: none;
      background-color: yellow;
    }
    h2 { 
      font-size: large;
      font-weight: bold;
    }
  </style>
  </head>
  <body>
  <h1>CBETA #{@v2} 變更記錄</h1>)
  end

  def n2s(number)
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def parse_diff_text(text)
    r = ''

    text.scan(/Only in (.*): (.*)/).each do |folder, fn|
      next if fn.start_with? '.'
      if folder.include? @v1
        @removed += "<li>#{folder}/#{fn}</li>\n"
      else
        if fn.match(/^[A-Z]{1,2}$/) # 新增一整部藏經
          add_canon(folder, fn)
        elsif fn.match(/^[A-Z]{1,2}\d{2,3}$/) # 新增一整冊
          rel_path = File.join(folder, fn)
          add_vol(rel_path)
        elsif fn.match(/^(\d{3})\.txt$/) # 新增一整卷
          juan = $1.to_i
          add_juan(folder, juan)
        else
          add_work(folder, fn)
        end
      end
    end
    
    text.scan(/diff -r \S+ \S+\n.*?(?=diff|\z)/m).each do |s|
      r += parse_patch(s)
    end
    r
  end

  def parse_patch(text)
    lines = text.split("\n")
    f1 = nil
    f2 = nil
    
    lines[0].match(/diff -r #{@old_nor}\/(\S+) #{@new_nor}\/(\S+)/) do
      f1 = $1
      f2 = $2
    end
    
    abort text if f1.nil? or f2.nil?
    
    tokens = f1.split('/')
    basename = tokens[2]
    juan = tokens.last.sub(/^0*(\d+)\.txt$/, '\1')
    work_id = CBETA.get_work_id_from_file_basename(basename)
    title = @titles[work_id]

    # 2019Q1 Y 重新分卷
    if @v2 == '2019Q1' and basename.start_with?('Y')
      return ''
    end
    
    r = parse_blocks(lines[2..-1])
    return '' if r.empty?
    
    @juans_count += 1
    "\n<h2>#{basename}《#{title}》卷#{juan}</h2>\n" + r
  end

  def parse_blocks(lines)
    text = lines.join("\n")
    blocks = text.split(/\n[\d,a-z]+\n/)
    r = ''
    blocks.each do |s|
      a = s.split("\n")
      r += parse_body(a)
    end
    r
  end

  def parse_body(lines)
    @log.puts("<h1>parse body</h1>")
    @log.puts(lines.join('<br>'))
    
    a1 = []
    a2 = []
    
    lines.each do |line|
      if line.start_with? '< '
        s = line[2..-1]
        if not s.include? '║' and not a1.empty?
          a1[-1] += s
        else
          a1 << s
        end
      elsif line.start_with? '> '
        s = line[2..-1]
        if not s.include? '║' and not a2.empty?
          a2[-1] += s
        else
          a2 << s
        end
      end
    end
    
    i = [a1.size, a2.size].max
    @lines_count += i  
    r = ""
    
    diff_html = nil
    # 逐行比對差異
    until a1.empty? or a2.empty?
      s1 = a1.first
      s2 = a2.first.sub(/^\s*(.*)$/, '\1')

      if same_text_and_puncs(s1, s2) # 忽略全形空格差異
        @lines_count -= 1
        a1.shift
        a2.shift
        next
      end

      linehead1 = s1.include?('║') ? s1.sub(/^(.*?)║.*$/, '\1') : nil
      linehead2 = s2.include?('║') ? s2.sub(/^(.*?)║.*$/, '\1') : nil

      if linehead1.nil? and not linehead2.nil?
        r += diff_chars(s1, '') + "<br>\n"
        a1.shift
        next
      end

      if linehead1 == linehead2
        if same_text(s2, s1)
          diff_html = diff_puncs(s1, s2)
        else
          diff_html = diff_chars(s1, s2)
        end
        r += diff_html + "<br>\n"
        a1.shift
        a2.shift
        next
      end

      if a2.size > 1 and a2[1].start_with?(linehead1)
        r += diff_chars('', s2) + "<br>\n"
        a2.shift
        next
      end

      unless (a2.empty? or linehead1.nil?)
        r += diff_chars(s1, '') + "\n"
        a1.shift
        next
      end

      break
    end
    
    unless a1.empty? and a2.empty?
      s1 = a1.join("\n")
      s2 = a2.join("\n")
    
      s = diff_chars(s1, s2)
      s.gsub("\n", "<br>")
      r += s
    end
    r
  end

  def read_titles
    fn = File.join(@config[:metadata], 'titles/all-title-byline.csv')
    r = {}
    CSV.foreach(fn, headers: true) do |row|
      id = row['典籍編號']
      r[id] = row['典籍名稱']
    end
    r
  end

  def remove_puncs(s)
    s.gsub(@puncs_regexp, '')
  end

  def same_text(s1, s2)
    s3 = remove_puncs(s1)
    s4 = remove_puncs(s2)
    return s3==s4
  end

  def same_text_and_puncs(s1, s2)
    s3 = s1.gsub(/　/, '')
    s4 = s2.gsub(/　/, '')
    return s3==s4
  end

  # 字串轉為矩陣
  # 組字式 當做一個字
  # 英、梵、巴 一個 word 當做一個字
  def s2a(s)
    s.scan(WORD)
  end


end