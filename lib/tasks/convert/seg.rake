namespace :convert do  
  desc "將 純文字版 自動分詞"
  task :seg, [:canon] => :environment do |t, args|
    c = ConvertSeg.new
    c.convert(args[:canon])
  end
end

require 'tmpdir'
require 'zip'

class ConvertSeg
    
  def convert(canon)
    t1 = Time.now
    @canon = canon
    @model = Rails.configuration.x.seg_model
    @src_root = File.join(Rails.configuration.cb.dl, 'text')
    @dest_root = Rails.root.join('data', 'txt-seg')
    tmp_root = Rails.root.join('tmp')
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("cbdata_word_seg", tmp_root) do |dir|
      @tmp_dir = File.expand_path(dir)
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
    puts ElapsedTime.label(t1)
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
        FileUtils.mkdir_p(File.dirname(txt_path))
        entry.get_input_stream do |input_stream|
          File.binwrite(txt_path, input_stream.read)
        end
        remove_comment(txt_path)
        seg_file(txt_path, dest_path)
      end
    end
    File.delete(txt_path) if File.exist?(txt_path)
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
    raise 'auto-seg.rb 未回傳輸出檔' unless File.exist?(dest)

    print 'done. '
  end

end
