require_relative 'cbeta_p5a_share'

class CheckCover

  def initialize
    @xml = Rails.application.config.cbeta_xml
    @base = File.join(Rails.configuration.x.git, 'ebook-covers')
  end
  
  def check
    @errors = ''

    each_canon(@xml) do |canon|
      check_canon(canon)
    end

    if @errors.empty?
      puts "檢查 ebook 封面成功，無錯誤。".green
    else
      puts @errors.red
    end
  end
  
  private

  def check_canon(canon)
    src = File.join(@xml, canon)
    Dir["#{src}/**/*.xml"].sort.each do |fn|
      bn = File.basename(fn)
      $stderr.puts "check ebook cover: #{bn}"
      work = CBETA.get_work_id_from_file_basename(bn)
      cover = File.join(@base, canon, "#{work}.jpg")
      unless File.exist?(cover)
        @errors << "#{bn} #{cover} 不存在\n"
      end
    end
  end

  include CbetaP5aShare
end