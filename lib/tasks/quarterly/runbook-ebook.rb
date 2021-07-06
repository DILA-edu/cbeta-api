require 'runbook'

module RunbookSectionEbook
  def define_section_ebook(config)
    Runbook.section "製作電子書" do
      step '製作 EPUB' do
        ruby_command do |rb_cmd, metadata, run|
          require_relative 'epub-main'
          CbetaEbook.new(config).convert
        end
      end

      step '壓縮全部 EPUB' do
        ruby_command do |rb_cmd, metadata, run|
          q = config[:q2].downcase
          dest = "cbeta-epub-#{q}.zip"
          
          # 變更目前目錄再做壓縮，否則壓縮檔內會含路徑
          Dir.chdir(config[:download]) do
            FileUtils.remove_file(dest, force: true)
            system "zip -r #{dest} epub"
          end

          puts "交由 heaven 將 EPUB 轉為 MOBI, PDF:"
          puts "https://cbdata.dila.edu.tw/dev/download/cbeta-epub-#{q}.zip"
        end
      end

    end
  end
end
