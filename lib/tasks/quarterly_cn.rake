desc "每季執行 (停用)"
task :quarterly_cn, [:env] => :environment do |t, args|
  require_relative 'quarterly/config'
  include Config
  config = get_config('cn')

  require_relative 'quarterly/runbook-prepare-cn'
  include PrepareCN
  section_prepare = define_section_prepare(config)

  require_relative 'quarterly/runbook-rdb'
  include RunbookSectionRDB
  section_rdb = define_section_rdb(config)

  require_relative 'quarterly/runbook-convert'
  include RunbookSectionConvert
  section_convert = define_section_convert(config)

  require_relative 'quarterly/runbook-sphinx-cn'
  include RunbookSectionSphinxCN
  section_sphinx = define_section_sphinx(config)

  require_relative 'quarterly/runbook-ebook-cn'
  include RunbookSectionEbookCN
  section_ebook = define_section_ebook(config)

  runbook = Runbook.book "CBData Quarterly" do
    description "CBData 每季更新\n"
    add section_prepare
    add section_rdb
    add section_convert
    add section_sphinx
    add section_ebook
  end

  work_dir = Rails.root.join('lib', 'tasks', 'quarterly')
  Dir.chdir(work_dir) do
    #$stdout = STDERR
    Runbook::Runner.new(runbook).run
  end
  
end
