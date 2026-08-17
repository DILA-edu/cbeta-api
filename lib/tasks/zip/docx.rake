# frozen_string_literal: true

namespace :zip do
  desc 'zip docx 一經一檔'
  task docx: :environment do
    t1 = Time.now
    DownloadZipper.new(:docx).zip
    puts ElapsedTime.label(t1)
  end
end
