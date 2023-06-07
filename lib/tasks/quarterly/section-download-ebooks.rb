module SectionDownloadEbooks
  def run_section_download_ebooks
    run_section "從 CBETA 下載 Heaven 製作的 EPUB, Mobi, PDF 電子書" do
      run_step '下載 EPUB, Mobi, PDF' do
        command 'rake download:ebooks'
      end
    end
  end
end
