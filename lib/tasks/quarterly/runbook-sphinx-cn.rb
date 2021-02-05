require 'runbook'

module RunbookSectionSphinxCN
  def define_section_sphinx(config)
    Runbook.section "Sphinx" do
      step '先把 XML P5a 轉為 text' do
        confirm '如果欄位有變更，要修改： /etc/sphinxsearch/sphinx.conf'
        command 'rake sphinx:x2t'
      end

      step '轉出 sphinx 所需的 xml' do
        confirm <<~MSG
        需要部類、時間資訊，要執行過：
          rake import:category
          rake import:time
        MSG
        command 'rake sphinx:t2x'
        command 'rake sphinx:footnotes'
        command 'rake sphinx:titles'
      end

      step 'sphinx 建資料夾' do
        ruby_command do |rb_cmd, metadata, run|
          Dir.chdir('/mnt/CBETAOnline/sphinxsearch') do
            %w[data7 footnotes titles].each do |s|
              system "sudo mkdir #{s}"
              system "sudo chown -R ray:sphinxsearch #{s}"
            end
          end
        end
      end

      step 'sphinx index' do
        command "sudo indexer --rotate cbeta7"
        command "sudo indexer --rotate footnotes"
        command "sudo indexer --rotate titles"
        command 'sudo service sphinxsearch restart'
        note '可手動清除舊版 Index: /var/lib/sphinxsearch'
        note '注意 /var/lib/sphinxsearch/data 不能刪。'
      end

      step '匯入 異體字 (rake import:vars)' do
        confirm '這要在 Sphinx Index 建好之後才能執行'
        note '資料來源是 https://github.com/DILA-edu/cbeta-metadata/blob/master/variants/variants.json'
        command 'rake import:vars'
      end
  
    end
  end
end