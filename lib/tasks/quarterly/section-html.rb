module SectionHTML
  def run_section_html
    run_section "產生 HTML 供 Heaven 比對 (section-html.rb)" do
      run_step 'convert xml to html (rake convert:x2h)' do
        require_relative '../convert_x2h'
        c = ConvertX2h.new
        c.convert(@config[:publish])
      end
  
      run_step '匯入佛寺志等 Layers' do
        command "rake import:layers"
      end
  
      run_step '打包 html 給 heaven' do
        step_zip_html
      end
    end
  end

  def step_zip_html
    # 變更目前目錄再做壓縮，否則壓縮檔內會含路徑
    Dir.chdir(@config[:data]) do
      # 先刪除舊檔, 否則 zip 裡的舊檔會保留
      FileUtils.remove_file('html.zip', force: true)
      command "zip -r html.zip html"
    end

    src = File.join(@config[:data], 'html.zip')
    confirm <<~MSG
      將 zip 檔提供給 heaven:
        #{src}
        =>
        GoogleDrive/共用雲端硬碟/CBETA-API/out/html.zip
      因為 heaven 可能發現問題再修改 XML，
      所以等 heaven 比對完再進行後面的步驟。
    MSG
  end
end # end of module
