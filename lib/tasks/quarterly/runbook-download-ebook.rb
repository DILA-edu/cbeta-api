require 'runbook'

module RunbookSectionDownloadEbooks
  def define_section_download_ebook(config)
    Runbook.section "從 CBETA 下載 Heaven 製作的 EPUB, Mobi, PDF 電子書" do
      step '下載 EPUB, Mobi, PDF' do
        command 'rake download:ebooks'
      end
    end
  end
end
