require 'chronic_duration'
require 'zip'

class ConvertSeg
    
  def convert(canon)
    t1 = Time.now
    @canon = canon
    @model = Rails.configuration.x.seg_model
    @src_root = Rails.root.join('data', 'download', 'text')
    @dest_root = Rails.root.join('data', 'txt-seg')

    Dir.mktmpdir("cbdata_word_seg") do |dir|
      @tmp_dir = dir
      Dir.entries(@src_root).sort.each do |f|
        next if f.start_with? '.'
        next unless f.include? '_'

        @work_id = f.sub(/^(.*?)_.*$/, '\1')
        if canon.nil?
          @canon = CBETA.get_canon_id_from_work_id(@work_id)
        else
          next unless f.start_with? canon
        end

        convert_file(f)
      end
    end
    puts "花費時間：" + ChronicDuration.output(Time.now - t1)
  end

  private

  def convert_file(fn)
    zip_file_path = File.join(@src_root, fn)
    txt_fn = File.basename(fn, '.zip')
    print "\n#{txt_fn} "
    txt_path = File.join(@tmp_dir, txt_fn)

    dest_folder = File.join(@dest_root, @canon, @work_id)
    FileUtils.makedirs dest_folder
    dest_path = File.join(dest_folder, txt_fn)

    Zip::File.open(zip_file_path) do |zip_file|
      zip_file.each do |entry|
        next unless entry.name.end_with? '.txt'
        print "extract #{entry.name} "
        entry.extract(txt_path)
        remove_comment(txt_path)
        seg_file(txt_path, dest_path)
      end
    end
    File.delete(txt_path)
  end

  def remove_comment(fn)
    print "remove_comment "
    s = ''
    File.foreach(fn) do |line|
      next if line.start_with? '#'
      s << line
    end
    File.write(fn, s)
  end

  def seg_file(src, dest)
    print "seg_file..."
    Dir.chdir(Rails.configuration.x.seg_bin) do
      `ruby auto-seg.rb #{@model} #{src} #{dest}`
    end
    unless File.exist? dest
      abort = 'auto-seg.rb 未回傳輸出檔'
    end
    print 'done. '
  end

end
