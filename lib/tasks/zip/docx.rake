# frozen_string_literal: true

namespace :zip do
  desc 'zip docx 一經一檔, 並產生全套的 cbeta-docx.zip'
  task docx: :environment do
    t1 = Time.now
    DownloadZipper.new(:docx, bundle: true).zip
    puts ElapsedTime.label(t1)
  end
end
