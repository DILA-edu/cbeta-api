class WordSegService
  def run(s)
    r = nil
    model = Rails.configuration.x.seg_model
    Dir.mktmpdir("cbdata_word_seg") do |dir|
      f1 = File.join(dir, '1.txt')
      f2 = File.join(dir, '2.txt')
      File.write(f1, s)
      Dir.chdir(Rails.configuration.x.seg_bin) do
        `ruby auto-seg.rb #{model} #{f1} #{f2}`
      end

      if File.exist? f2
        s = File.read(f2)
        r = OpenStruct.new(success?: true, result: s)
      else
        r = OpenStruct.new(success?: false, errors: 'auto-seg.rb 未回傳輸出檔')
      end
    end
    r
  end
end
