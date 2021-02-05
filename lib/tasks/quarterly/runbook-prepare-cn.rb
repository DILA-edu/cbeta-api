#require 'net/sftp'
require 'runbook'

module PrepareCN
  def define_section_prepare(config)
    Runbook.section "前置作業 (runbook-prepare.rb)" do
      step 'update_from_github (update-github.rb)' do
        command "ruby update-github.rb #{config[:git]}"
      end

      step '產生 Juanline 資料 (juanline.rb)' do
        ruby_command do |rb_cmd, metadata, run|
          require_relative 'juanline'
          Juanline.new.produce
        end
      end

      step '匯入缺字資料' do
        command 'rake db:migrate'
        command 'rake import:gaiji'
      end

      step 'convert xml to html (rake convert:x2h)' do
        command "rake convert:x2h[#{config[:publish]}]"
      end

    end
  end
end