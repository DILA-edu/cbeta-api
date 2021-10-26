require 'runbook'

module RunbookSectionMobi
  def define_section_mobi(config)
    Runbook.section "從 CBETA 下載 Heaven 製作的 Mobi, PDF 電子書" do
      step '下載 Mobi, PDF' do
        ruby_command do |rb_cmd, metadata, run|
          q = config[:q2].downcase
          dest = "cbeta-epub-#{q}.zip"
          a = ["pdf_a4/cbeta_pdf_1_#{q}", "pdf_a4/cbeta_pdf_2_#{q}", "pdf_a4/cbeta_pdf_3_#{q}", "mobi/cbeta_mobi_#{q}"]
          Dir.chdir(config[:download]) do
            a.each do |s|
              cmd = "curl -C - -O https://archive.cbeta.org/download/#{s}.zip"
              i = 1
              loop do
                puts "#{i} ----------"
                puts(cmd)
                break if system(cmd)
              end
            end

            system "mv mobi mobi.old"
            system "unzip cbeta_mobi_#{q}.zip"
            system "mv cbeta_mobi_#{q} mobi"
            system "rm -rf mobi.old"
            system "mv cbeta_mobi_#{q}.zip cbeta-mobi-#{q}.zip"

            (1..3).each do |i|
              system "unzip cbeta_pdf_#{i}_#{q}.zip"
              system "mv cbeta_pdf_#{i}_#{q}.zip cbeta-pdf-#{q}-#{i}.zip"
            end

            system "rm -rf pdf"
            system "mv cbeta_pdf_1_#{q} pdf"

            system "mv cbeta_pdf_2_#{q}/* pdf"
            system "rm -rf cbeta_pdf_2_#{q}"

            system "mv cbeta_pdf_3_#{q}/* pdf"
            system "rm -rf cbeta_pdf_3_#{q}"

          end
        end
      end
    end
  end
end
