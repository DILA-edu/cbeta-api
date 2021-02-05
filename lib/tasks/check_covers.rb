class CheckCover

  def initialize
    @base = File.join(Rails.configuration.x.git, 'ebook-covers')
  end
  
  def check
    src = Rails.application.config.cbeta_xml
    errors = ''
    Dir["#{src}/**/*.xml"].sort.each do |fn|
      bn = File.basename(fn)
      $stderr.puts "check ebook cover: #{bn}"
      work = CBETA.get_work_id_from_file_basename(bn)
      canon = CBETA.get_canon_id_from_work_id(work)
      cover = File.join(@base, canon, "#{work}.jpg")
      unless File.exist?(cover)
        errors << "#{bn} #{cover} 不存在\n"
      end
    end
    if errors.empty?
      puts "檢查 ebook 封面成功，無錯誤。".green
    else
      puts errors.red
    end
  end
  
  private

end