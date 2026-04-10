module SectionHTML
  def run_section_html
    run_section "產生 HTML 供 Heaven 比對 (section-html.rb)" do
      run_step 'convert xml to html (rake convert:x2h)' do
        command "rake 'convert:x2h[#{@config[:publish]}]'"
      end
  
      run_step '匯入佛寺志等 Layers' do
        command "rake import:layers"
      end
  
      run_step 'check to html (rake check:html)' do
        command 'rake check:html'
      end

      run_step '打包 html 給 heaven' do
        step_zip_html
      end
    end
  end

  def step_zip_html
    t = Time.now.strftime('%Y-%m-%d-%H%M')
    dest = Rails.root.join("public", "download", "html-#{t}.zip")

    # 變更目前目錄再做壓縮，否則壓縮檔內會含路徑
    Dir.chdir(@config[:data]) do
      # 先刪除舊檔, 否則 zip 裡的舊檔會保留
      FileUtils.remove_file(dest, force: true)
      command "zip -r #{dest} html"
    end

    src = File.join(@config[:data], 'html.zip')
    confirm <<~MSG
      將 zip 檔提供給 heaven:
        #{dest}
      因為 heaven 可能發現問題再修改 XML，
      所以等 heaven 比對完再進行後面的步驟。
    MSG
  end
end # end of module
