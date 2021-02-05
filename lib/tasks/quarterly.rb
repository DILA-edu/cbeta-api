class Quarterly
  require_relative 'quarterly/config'
  require_relative 'quarterly/runbook-prepare'
  require_relative 'quarterly/runbook-check'
  require_relative 'quarterly/runbook-html'
  require_relative 'quarterly/runbook-change-log'
  require_relative 'quarterly/runbook-rdb'
  require_relative 'quarterly/runbook-convert'
  require_relative 'quarterly/runbook-ebook'
  require_relative 'quarterly/runbook-sphinx'
  require_relative 'quarterly/runbook-kwic'

  def initialize(env)
    @config = get_config(env)
    puts "Environment: #{@config[:env]}"
    @book = define_runbook(@config)
    @work_dir = Rails.root.join('lib', 'tasks', 'quarterly')
  end

  def run
    Dir.chdir(@work_dir) do
      Runbook::Runner.new(@book).run
    end
  end

  def view
    Dir.chdir(@work_dir) do
      text = Runbook::Viewer.new(@book).generate(view: :markdown)
      text.split("\n").each do |s|
        next if s.empty?
        next if s.start_with?(' ')
        if s.start_with?('#')
          puts
        else
          s = '  ' + s
        end
        puts s
      end
    end
  end

  def self.copy_folder(src, dest, exclude=[])
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
  include Prepare
  include Check
  include RunbookSectionHTML
  include RunbookSectionChangeLog
  include RunbookSectionRDB
  include RunbookSectionConvert
  include RunbookSectionEbook
  include RunbookSectionSphinx
  include RunbookSectionKwic

  def define_runbook(config)
    section_prepare    = define_section_prepare(config)
    section_check      = define_section_check(config)
    section_html       = define_section_html(config)
    section_change_log = define_section_change_log(config)
    section_rdb        = define_section_rdb(config)
    section_convert    = define_section_convert(config)
    section_ebook      = define_section_ebook(config)
    section_sphinx     = define_section_sphinx(config)
    section_kwic       = define_section_kwic(config)
  
    Runbook.book "CBData Quarterly" do
      description "CBData 每季更新\n"
      add section_prepare
      add section_check
      unless config[:env] == 'staging'
        add section_html
        add section_change_log
      end
      add section_rdb
      add section_convert
      add section_sphinx
      add section_ebook unless config[:env] == 'staging'
      add section_kwic  unless config[:env] == 'staging'
    end
  end
end