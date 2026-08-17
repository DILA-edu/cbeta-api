# frozen_string_literal: true

namespace :zip do
  desc 'zip odt 一經一檔, 並產生全套的 cbeta-odt.zip'
  task odt: :environment do
    t1 = Time.now
    DownloadZipper.new(:odt, bundle: true).zip
    puts ElapsedTime.label(t1)
  end
end
