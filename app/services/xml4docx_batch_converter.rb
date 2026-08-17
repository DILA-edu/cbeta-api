# frozen_string_literal: true

require 'etc'
require 'json'

# 把 data/xml4docx 整批轉成 public/download/<format>, 以多 process 平行處理。
#
#   Xml4docxBatchConverter.new(:odt, filter: 'T01', workers: 8).convert
class Xml4docxBatchConverter
  # 每種警告在 log 裡最多列幾個來源檔案
  WARNING_SAMPLE_SIZE = 5

  FORMATS = {
    docx: XmlToDocxConverter,
    odt: XmlToOdtConverter
  }.freeze

  def initialize(format, filter: nil, workers: nil)
    @format = format.to_sym
    @converter = FORMATS.fetch(@format) { raise ArgumentError, "未支援的格式: #{format}" }
    @filter = filter
    @workers = (workers || Etc.nprocessors).to_i.clamp(1, 64)
    @src = Rails.root.join('data/xml4docx')
    @dest = Rails.root.join('public/download', @format.to_s)
    @figures = Rails.configuration.x.figures
  end

  def convert
    files = source_files
    if files.empty?
      puts "找不到符合的 xml4docx 檔案: #{@src}"
      return
    end

    prepare_dest
    puts "xml4docx 轉 #{@format}: #{files.size} 檔, #{@workers} workers"
    puts "figures: #{@figures}"
    puts "輸出: #{@dest}"

    results = @workers > 1 ? convert_in_parallel(files) : [convert_files(files, total: files.size)]
    report(results)
  end

  private

  def source_files
    files = Dir.glob("#{@src}/**/*.xml", sort: true)
    files.select! { it.include?(@filter) } if @filter.present?
    files
  end

  def prepare_dest
    # 有 filter 時只補轉部分典籍, 不清空既有成果
    @dest.rmtree if @filter.blank? && @dest.exist?
    @dest.mkpath
  end

  def convert_in_parallel(files)
    # 交錯分配, 讓各 worker 拿到的檔案大小較平均
    slices = files.group_by.with_index { |_file, i| i % @workers }.values
    $stdout.flush
    ActiveRecord::Base.connection_handler.clear_all_connections!

    readers = []
    slices.each_with_index do |slice, index|
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        # 只讓第一個 worker 印進度, 以它的進度乘上 worker 數估算整體進度
        writer.write(JSON.generate(convert_files(slice, total: index.zero? ? files.size : nil)))
        writer.close
        exit!(0)
      end
      writer.close
      readers << [pid, reader]
    end

    # 先讀完 pipe 再等 child 結束, 避免 pipe buffer 塞滿造成 deadlock
    results = readers.map { |_pid, reader| JSON.parse(reader.read, symbolize_names: true).tap { reader.close } }
    readers.each { |pid, _reader| Process.wait(pid) }
    results
  end

  def convert_files(files, total: nil)
    errors = []
    warnings = Hash.new { |hash, message| hash[message] = { count: 0, files: [] } }

    files.each_with_index do |src, i|
      dest = dest_path(src)
      dest.dirname.mkpath
      begin
        @converter.new(src, figures_dir: @figures).convert(dest.to_s).each do |message|
          entry = warnings[message]
          entry[:count] += 1
          entry[:files] << src if entry[:files].size < WARNING_SAMPLE_SIZE
        end
      rescue StandardError => e
        errors << "#{src}: #{e.class}: #{e.message}"
      end
      print_progress(i, files.size, total) if total
    end

    { count: files.size, errors: errors, warnings: warnings.map { |message, entry| entry.merge(message: message) } }
  end

  # 平行時只有一個 worker 在印, 用它的進度估算整體
  def print_progress(index, worker_total, total)
    done = worker_total == total ? index + 1 : [(index + 1) * @workers, total].min
    print "\rconvert:#{@format} #{done}/#{total}  "
  end

  def dest_path(src)
    relative = Pathname.new(src).relative_path_from(@src)
    @dest.join(relative.sub_ext(".#{@format}"))
  end

  def report(results)
    count = results.sum { it[:count] }
    errors = results.flat_map { it[:errors] }
    warnings = merge_warnings(results)

    puts "\n完成 #{count} 檔, 錯誤 #{errors.size} 筆, 警告 #{warnings.sum { it[:count] }} 筆"
    warnings.first(10).each { puts "  警告 x#{it[:count]}: #{it[:message]}" }
    errors.first(10).each { puts "  錯誤: #{it}" }
    write_log(errors, warnings)
  end

  def merge_warnings(results)
    merged = Hash.new { |hash, message| hash[message] = { message: message, count: 0, files: [] } }
    results.each do |result|
      result[:warnings].each do |warning|
        entry = merged[warning[:message]]
        entry[:count] += warning[:count]
        entry[:files] = (entry[:files] + warning[:files]).first(WARNING_SAMPLE_SIZE)
      end
    end
    merged.values.sort_by { -it[:count] }
  end

  def write_log(errors, warnings)
    lines = warnings.map do |warning|
      ["警告 x#{warning[:count]}: #{warning[:message]}", *warning[:files].map { "  例: #{it}" }]
    end
    path = Rails.root.join("log/convert_#{@format}.log")
    path.write("#{(lines.flatten + errors).join("\n")}\n")
    puts "log: #{path}"
  end
end
