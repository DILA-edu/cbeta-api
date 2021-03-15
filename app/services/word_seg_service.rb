class WordSegService
  def run(s)
    r = nil
    model = Rails.configuration.x.seg_model.to_s
    Dir.mktmpdir("cbdata_word_seg") do |dir|
      f1 = File.join(dir, '1.txt')
      f2 = File.join(dir, '2.txt')
      File.write(f1, s)
      Dir.chdir(Rails.configuration.x.seg_bin) do
        #`ruby  #{model} #{f1} #{f2}`
        stdout, stderr, status = Open3.capture3("ruby", "auto-seg.rb", model, f1, f2)
        if status.success?
          if File.exist? f2
            s = File.read(f2)
            r = OpenStruct.new(success?: true, result: s)
          else
            r = OpenStruct.new(success?: false, errors: 'auto-seg.rb 未回傳輸出檔')
          end
        else
          r = OpenStruct.new(success?: false, errors: stdout + "\n" + stderr)
        end
      end
    end
    r
  end
end
