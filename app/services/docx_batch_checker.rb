# frozen_string_literal: true

require 'json'

# 用 DocxChecker 整批比對 data/xml4docx 與 public/download/docx, 以多 process 平行處理。
#
#   DocxBatchChecker.new(filter: 'T01', workers: 8).check  # => 有錯誤的檔案數
class DocxBatchChecker
  def initialize(filter: nil, workers: nil)
    @filter = filter
    @workers = BatchWorkers.count(workers)
    @src = Rails.root.join('data/xml4docx')
    @dest = Rails.root.join('public/download/docx')
  end

  def check
    BatchWorkers.lower_priority!
    files = source_files
    puts "check:docx #{files.size} 檔, #{@workers} workers"
    failures = @workers > 1 ? check_in_parallel(files) : check_files(files, total: files.size)
    failures += orphan_failures
    report(files.size, failures)
    failures.size
  end

  private

  def source_files
    files = Dir.glob("#{@src}/**/*.xml", sort: true)
    files.select! { it.include?(@filter) } if @filter.present?
    files
  end

  # 與 Xml4docxBatchConverter 相同的 fork + pipe 做法
  def check_in_parallel(files)
    slices = files.group_by.with_index { |_file, i| i % @workers }.values
    $stdout.flush

    readers = slices.each_with_index.map do |slice, index|
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        writer.write(JSON.generate(check_files(slice, total: index.zero? ? files.size : nil)))
        writer.close
        exit!(0)
      end
      writer.close
      [ pid, reader ]
    end

    # 先讀完 pipe 再等 child 結束, 避免 pipe buffer 塞滿造成 deadlock
    results = readers.flat_map { |_pid, reader| JSON.parse(reader.read).tap { reader.close } }
    readers.each { |pid, _reader| Process.wait(pid) }
    results
  end

  # 回傳 [[檔名, [錯誤訊息...]], ...], 只含有錯誤的檔案
  def check_files(files, total: nil)
    files.each_with_index.filter_map do |src, i|
      print_progress(i, files.size, total) if total
      errors = check_file(src)
      [ relative(src), errors ] if errors.any?
    end
  end

  def check_file(src)
    docx = docx_path(src)
    errors = DocxChecker.new(src, docx).check
    if errors.empty? && File.mtime(docx) < File.mtime(src)
      errors << 'docx 比 xml4docx 舊, 可能需要重新 convert:docx'
    end
    errors
  rescue StandardError => e
    [ "#{e.class}: #{e.message}" ]
  end

  # 有 docx 卻沒有對應的 xml4docx, 多半是典籍改號或刪除後殘留的舊檔
  def orphan_failures
    Dir.glob("#{@dest}/**/*.docx", sort: true).filter_map do |docx|
      next if @filter.present? && !docx.include?(@filter)

      src = @src.join(Pathname.new(docx).relative_path_from(@dest).sub_ext('.xml'))
      [ Pathname.new(docx).relative_path_from(Rails.root).to_s, [ '沒有對應的 xml4docx' ] ] unless src.exist?
    end
  end

  def print_progress(index, worker_total, total)
    done = worker_total == total ? index + 1 : [ (index + 1) * @workers, total ].min
    print "\rcheck:docx #{done}/#{total}  "
  end

  def docx_path(src)
    @dest.join(Pathname.new(src).relative_path_from(@src).sub_ext('.docx'))
  end

  def relative(src)
    Pathname.new(src).relative_path_from(@src).to_s
  end

  def report(count, failures)
    lines = failures.flat_map { |file, errors| [ file, *errors.map { "  #{it}" } ] }
    path = Rails.root.join('log/check_docx.log')
    path.write(lines.empty? ? '' : "#{lines.join("\n")}\n")

    puts
    if failures.empty?
      puts "#{count} 檔未發現錯誤".green
    else
      puts lines.first(30)
      puts "\n#{count} 檔中有 #{failures.size} 檔發現錯誤".red
    end
    puts "log: #{path}"
  end
end
