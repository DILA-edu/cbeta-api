# 使用 Calibre 附的 command line 工具 ebook-convert
# https://manual.calibre-ebook.com/generated/en/ebook-convert.html

require 'colorize'
require 'fileutils'

class Epub2Mobi
  def initialize(config)
    @converter = config[:ebook_convert]
    @epub_base = config[:epub]
    @mobi_base = config[:mobi]
  end

  def convert
    Dir.entries(@epub_base).sort.each do |c|
      next if c.start_with?('.')
      p1 = File.join(@epub_base, c)
      p2 = File.join(@mobi_base, c)
      convert_canon(p1, p2)
    end
  end

  private

  def convert_canon(src, dest)
    FileUtils.makedirs(dest)
  
    Dir.entries(src).sort.each do |f|
      next if f.start_with?('.')
      p1 = File.join(src, f)
      p2 = File.join(dest, f.sub(/\.epub$/, '.mobi'))
      cmd = "#{@converter} #{p1} #{p2}"
      puts '-' * 10
      puts File.basename(f, '.*').green
      puts cmd
      abort unless system(cmd)
    end
  end
  
end