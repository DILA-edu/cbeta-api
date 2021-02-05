require 'runbook'

module RunbookSectionEbookCN
  def define_section_ebook(config)
    Runbook.section "從台灣下載電子書" do
      step '下載 EPUB' do
        ruby_command do |rb_cmd, metadata, run|
          q = config[:quarter].sub('.', '').downcase
          dest = "cbeta-epub-#{q}.zip"
          a = ["epub-#{q}", "mobi-#{q}", "pdf-#{q}-1", "pdf-#{q}-2"]
          Dir.chdir(config[:download]) do
            a.each do |s|
              cmd = "curl -C - -O http://cbdata.dila.edu.tw/dev/download/cbeta-#{s}.zip"
              i = 1
              loop do
                puts "#{i} ----------"
                puts(cmd)
                break if system(cmd)
              end
            end

            system "mv epub epub.old"
            system "unzip cbeta-epub-#{q}.zip"

            system "mv mobi mobi.old"
            system "unzip cbeta-mobi-#{q}.zip"

            system "mv pdf pdf.old"
            system "unzip cbeta-pdf-#{q}-1.zip"
            system "unzip cbeta-pdf-#{q}-2.zip"
          end
        end
      end
    end
  end
end
