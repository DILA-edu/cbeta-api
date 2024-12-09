require 'ostruct'
require_relative 'crf'

class WordSegService
  def run(text)
    crf = Crf.new(Rails.configuration.x.word_seg)
    s = text.gsub(/ /, '/')
    a = s.split(/([\n\/\.\(\)\[\]\-　．。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—◎])/)
    s_after_tag = ''
    a.each do |s|
      s_after_tag += crf.tag_string3(s, 'seg')
    end

    Dir.mktmpdir("word-seg") do |dir|
      src = File.join(dir, 'src.txt')
      File.write(src, s_after_tag)

      unless File.exist? src
        return OpenStruct.new(success?: false, errors: "寫檔發生錯誤: #{src}")
      end

      model = Rails.configuration.x.seg_model.to_s
      dest = File.join(dir, 'dest.txt')
      cmd = "crf_test -m #{model} #{src} > #{dest}"
      stdout, stderr, status = Open3.capture3(cmd)
      if status.success?
        s = tag2slash(File.read(dest))
        return OpenStruct.new(success?: true, result: s)
      else
        return OpenStruct.new(success?: false, errors: stderr)
      end
    end
  end

  private

  def tag2slash(lines)
    r = ''
    lines.each_line do |s|
      s.chomp!
      next if s.empty?
      a = s.split
  
      if a.first == "\u2028"
        r += "\n"
      else
        r += case a.last
        when 'S' then '/' + a.first + '/'
        when 'B' then '/' + a.first
        when 'E' then a.first + '/'
        else a.first
        end
      end
    end
    r.gsub(/\/{2,}/, '/')
  end

end # end of class
