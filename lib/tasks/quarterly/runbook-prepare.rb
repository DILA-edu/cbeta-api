#require 'net/sftp'
require 'runbook'

module Prepare
  def define_section_prepare(config)
    step_copy_data_folder = define_step_copy_data_folder(config)
    step_copy_help   = define_step_copy_help(config)
    step_copy_public = define_step_copy_public(config)
    step_copy_layers = define_step_copy_layers(config)
    step_import_juanline = define_step_import_juanline(config)
    
    Runbook.section "前置作業 (runbook-prepare.rb)" do
      if config[:env] == 'staging'
        add step_copy_data_folder
        add step_copy_public

        #step 'Create symbolic link for figures to GitHub' do
        #  command "ln -sf #{config[:cbr_figures]} #{config[:figures]}"
        #end
        add step_import_juanline
      else
        step 'update_from_github (update-github.rb)' do
          command "ruby update-github.rb #{config[:git]}"
        end
  
        step 'check new canon (check-new-canon.rb)' do
          command "ruby check-new-canon.rb #{config[:git]}"
        end

        step '產生 Juanline 資料 (juanline.rb)' do
          ruby_command do |rb_cmd, metadata, run|
            require_relative 'juanline'
            Juanline.new.produce
          end
        end

        # import:layers 要用到，所以提早做
        add step_import_juanline
  
        add step_copy_help
        add step_copy_layers
      end
    end
  end

  def define_step_copy_data_folder(config)
    Runbook.step '從上一季複製 data 資料夾' do
      ruby_command do |rb_cmd, metadata, run|
        Quarterly.copy_folder(config[:old_data], config[:data], ['figures'])
      end
    end
  end

  def define_step_copy_help(config)
    Runbook.step '從上一季複製檔案 Help HTML' do
      ruby_command do |rb_cmd, metadata, run|
        src = File.join(config[:old], "public/help")
        dest = File.join(config[:public], 'help')
        Quarterly.copy_folder(src, dest)
      end
    end
  end

  def define_step_copy_layers(config)
    Runbook.step '從上一季複製 Layers' do
      ruby_command do |rb_cmd, metadata, run|
        src = File.join(config[:old_data], "layers")
        dest = File.join(config[:data], 'layers')
        Quarterly.copy_folder(src, dest)
      end
    end
  end

  def define_step_copy_public(config)
    Runbook.step '從上一季複製 public 資料夾' do
      ruby_command do |rb_cmd, metadata, run|
        %w[download help].each do |fn|
          src = File.join(config[:old], "public", fn)
          dest = File.join(config[:public], fn)

          if fn == 'download'
            exclude = ['cbeta-text']
          else
            exclude = []
          end
          
          Quarterly.copy_folder(src, dest, exclude)
        end
      end
    end
  end

  def define_step_import_juanline(config)
    Runbook.step '匯入 各卷起始行 (rake import:juanline)' do
      command 'bundle exec rake import:juanline'
    end
  end
end