require 'runbook'

module RunbookSectionHTML
  def define_section_html(config)
    step_zip_html = define_step_zip_html(config)
    
    Runbook.section "產生 HTML 供 Heaven 比對 (runbook-html.rb)" do
      step 'convert xml to html (rake convert:x2h)' do
        command "rake convert:x2h[#{config[:publish]}]"
      end

      step '匯入佛寺志等 Layers' do
        command "rake import:layers"
      end

      add step_zip_html
    end
  end # end of define_section_html

  def define_step_zip_html(config)
    Runbook.step '打包 html 給 heaven' do
      ruby_command do |rb_cmd, metadata, run|
        # 變更目前目錄再做壓縮，否則壓縮檔內會含路徑
        Dir.chdir(config[:data]) do
          # 先刪除舊檔, 否則 zip 裡的舊檔會保留
          FileUtils.remove_file('html.zip', force: true)
          system "zip -r html.zip html"
        end
      end
      confirm <<~MSG
        將 zip 檔提供給 heaven:
          GoogleDrive/共用雲端硬碟/CBETA-API/out/html.zip
        因為 heaven 可能發現問題再修改 XML，
        所以等 heaven 比對完再進行後面的步驟。
      MSG
    end
  end
end # end of module