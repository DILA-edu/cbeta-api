require 'runbook'

module RunbookSectionChangeLog
  def define_section_change_log(config)
    Runbook.section "製作 Change Log (runbook-change-log.rb)" do
      step 'XML P5a 轉 normal 版 for Change Log' do
        ruby_command do |rb_cmd, metadata, run|
          v = config[:q2]
          dest = File.join(config[:change_log], "cbeta-normal-#{v}")
          require_relative 'p5a_to_text'
          c = P5aToText.new(config[:xml], dest, gaiji_base: config[:gaiji])
          c.convert
        end
      end

      step '使用 diff 命令比對兩個版本 normal 產生 diff.txt' do
        ruby_command do |rb_cmd, metadata, run|
          Dir.chdir(config[:change_log]) do
            cmd = "diff -r cbeta-normal-#{config[:q1]} cbeta-normal-#{config[:q2]} > diff.txt"
            puts cmd
            system cmd
          end
        end
      end

      step '由 diff.txt 製作 HTML 版 Change Log' do
        ruby_command do |rb_cmd, metadata, run|
          require_relative 'diff-to-html'
          DiffToHTML.new(config).convert
        end
      end

      step '將 Change Log 分成 文字、標點 兩部分' do
        ruby_command do |rb_cmd, metadata, run|
          require_relative 'change-log-cat'
          ChangeLogCategory.new(config).run
          require_relative 'change-log-font'
          ChangeLogFont.new(config).run
        end
      end

      step 'HTML 轉 PDF版' do
        confirm <<~MSG
          1. HTML 檔頭定義 style body { font-family: "Hanazono Mincho C Regular"; } 就可以正確顯示 Ext B, C, D
          2. Ext E, F 要針對個別的字指定 { font-family: "Hanazono Mincho C Regular" } 才能正確顯示。
          3. Ext G 沒有字型，不能顯示，產生「變更紀錄」時不應使用 Ext G
          4. Windows 電腦安裝 Adobe Acrobat Pro，然後使用 Word 裡的「儲存為 Adobe PDF」功能。
        MSG
      end

    end
  end
end