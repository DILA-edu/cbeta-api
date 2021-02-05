require 'runbook'

module RunbookSectionKwic
  def define_section_kwic(config)
    Runbook.section "KWIC" do
      step 'kwic configuration' do
        ruby_command do |rb_cmd, metadata, run|
          fn = Rails.root.join('lib/tasks/quarterly/kwic-template.yml')
          template = File.read(fn)
          v = config[:v]
          s = template % { v: v }
          dest = File.join(config[:git], 'kwic25/config.yml')
          $stderr.puts "write #{dest}"
          File.write(dest, s)
        end
        confirm "檢視 kwic config 是否正確: #{config[:git]}/kwic25/config.yml"
      end

      step 'suffix array (約11小時)' do
        ruby_command do |rb_cmd, metadata, run|
          Dir.chdir("#{config[:git]}/kwic25") do
            system("ruby x2h.rb")
            system("ruby text-all.rb") # simple html => txt, 全部做一次大約花 7 小時
            system("ruby sa.rb")       # suffix array, 約4小時
            note '重排 info.dat, 為了加速讀取 info.dat, 根據 sa 的順序重排 info.dat'
            note '約 1小時46分'
            system("ruby sort-info.rb")
          end
        end
      end

      step '將 suffix array 移至正式資料夾使用' do
        ruby_command do |rb_cmd, metadata, run|
          Dir.chdir("#{config[:git]}/kwic25") do
            system("ruby rotate.rb")
          end
        end
      end
    end
  end
end