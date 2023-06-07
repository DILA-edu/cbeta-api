class Quarterly
  require_relative 'config'
  require_relative 'section-prepare'
  require_relative 'section-check'
  require_relative 'section-html'
  require_relative 'section-change-log'
  require_relative 'section-rdb'
  require_relative 'section-convert'
  require_relative 'section-sphinx'
  require_relative 'section-kwic'
  require_relative 'section-download-ebooks'

  def initialize
    @config = get_config
    puts "Environment: #{Rails.env}"
    @work_dir = Rails.root.join('lib', 'tasks', 'quarterly')
    @section_count = 0
    @step_count = 0
  end

  def run
    puts "CBData 每季更新"
    Dir.chdir(@work_dir) do
      run_section("前置作業 (prepare.rb)") { run_section_prepare }
      run_section("檢查作業 (check.rb)") { run_section_check }
      run_section("產生 HTML 供 Heaven 比對 (runbook-html.rb)") { run_section_html }
      run_section_change_log
      run_section_convert
      run_section_sphinx
      run_section_kwic
      run_section_download_ebooks
    end
  end

  def copy_folder(src, dest, exclude=[])
    puts "copy folder #{src} => #{dest}"
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
      if Dir.exist?(p1)
        self.copy_folder(p1, p2)
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
  include SectionSphinx
  include SectionKwic
  include SectionDownloadEbooks

  def command(cmd)
    puts cmd
    system cmd
  end

  def confirm(msg)
    puts msg
    puts "按任意鍵繼"
    STDIN.getch
  end

  def run_section(label)
    @section_count += 1
    @step_count = 0
    puts "\nSection #{@section_count}: #{label}"
    print 'Continue? 按 Enter 繼續，按 s 跳過 '
    input = STDIN.getch.chomp
    puts
    yield if input.empty?
  end

  def run_step(label)
    @step_count += 1
    puts "\nStep #{@section_count}.#{@step_count}: #{label}"
    print 'Continue? 按 Enter 繼續，按 s 跳過 '
    input = STDIN.getch.chomp
    puts
    yield if input.empty?
  end

end
