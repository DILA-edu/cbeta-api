class Quarterly
  require_relative 'config'
  require_relative 'section-prepare'
  require_relative 'section-check'
  require_relative 'section-html'
  require_relative 'section-change-log'
  require_relative 'section-rdb'
  require_relative 'section-convert'
  require_relative 'section-search-xml'
  require_relative 'section-elastic'
  require_relative 'section-kwic'
  require_relative 'section-download-ebooks'

  # interactive: false 時不等鍵盤輸入 (供 rake quarterly:step 使用),
  # confirm 的訊息照樣印出, 由執行者自行判讀。
  def initialize(interactive: true)
    @interactive = interactive
    @config = get_config
    puts "Environment: #{Rails.env}"
    confirm("請先確認 Rails 環境 是否正確")

    @work_dir = Rails.root.join('lib', 'tasks', 'quarterly')
    @section_count = 0
    @step_count = 0
  end

  def run
    puts "CBData 每季更新"
    Dir.chdir(@work_dir) do
      run_section_prepare
      run_section_check
      run_section_rdb
      run_section_html
      run_section_change_log
      run_section_convert
      #run_section_sphinx
      run_section_search_xml
      run_section_elastic
      run_section_kwic
      run_section_download_ebooks
    end
  end

  # 可單獨執行的步驟 (各 section 裡的 step_* method)
  def self.step_names
    (instance_methods + private_instance_methods).grep(/\Astep_/).sort
  end

  # 非互動執行單一步驟
  def run_one_step(name)
    name = name.to_s.strip
    name = "step_#{name}" unless name.start_with?('step_')
    unless self.class.step_names.include?(name.to_sym)
      abort "沒有這個步驟: #{name}\n可用的步驟: rake quarterly:steps"
    end

    Dir.chdir(@work_dir) { send(name) }
  end

  def copy_folder(src, dest, exclude: [], verbose: true)
    return if File.symlink?(src)

    puts "[#{Time.now}] copy folder #{src} => #{dest}" if verbose
    if Dir.exist?(dest)
      print "remove old folder #{dest}..."
      `rm -rf #{dest}`
      puts 'done'
    end
    Dir.mkdir(dest)
    Dir.entries(src).sort.each do |f|
      next if f.start_with?('.')
      next if exclude.include?(f)
      
      p1 = File.join(src, f)
      p2 = File.join(dest, f)
      next if File.symlink?(p1)

      puts "[#{Time.now}] copy folder #{p1} => #{p2}" if verbose
      if Dir.exist?(p1)
        next if f.match?(/\d{4}-\d\d-\d\d-\d{6}$/)
        copy_folder(p1, p2, verbose: false)
      else
        if File.size(p1) > 100_000_000
          `cp #{p1} #{p2} & progress -mp $!` # show progress
        else
          FileUtils.copy_file(p1, p2)
        end
      end
    end
  end

  private

  include Config
  include SectionPrepare
  include SectionCheck
  include SectionHTML
  include SectionChangeLog
  include SectionRDB
  include SectionConvert
  #include SectionSphinx
  include SectionSearchXml
  include SectionElastic
  include SectionKwic
  include SectionDownloadEbooks

  def command(cmd)
    puts cmd
    unless system(cmd)
      abort "執行 command 發生錯誤"
    end
  end

  def confirm(msg)
    puts msg
    unless @interactive
      puts '(非互動模式, 不等待確認)'
      return
    end

    print "按 q 脫離，按任意鍵繼續："
    c = STDIN.getch
    puts
    abort if c == 'q'
  end

  def run_section(label)
    @section_count += 1
    @step_count = 0
    puts "\nSection #{@section_count}: #{label}"
    print 'Continue? 按 Enter 繼續，按 s 跳過，按 q 脫離 '
    c = STDIN.getch.chomp
    puts
    abort if c == 'q'
    yield if c.empty?
  end

  def run_step(label)
    @step_count += 1
    puts "\nStep #{@section_count}.#{@step_count}: #{label}"
    unless @interactive
      puts "[#{Time.now}] 開始"
      yield
      puts "[#{Time.now}] 結束"
      return
    end

    print 'Continue? 按 Enter 繼續，按 s 跳過，按 q 脫離 '
    c = STDIN.getch.chomp
    puts
    abort if c == 'q'
    yield if c.empty?
  end
end
