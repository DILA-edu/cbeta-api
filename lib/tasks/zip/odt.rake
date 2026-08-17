# frozen_string_literal: true

namespace :zip do
  desc 'zip odt 一經一檔'
  task odt: :environment do
    t1 = Time.now
    DownloadZipper.new(:odt).zip
    puts ElapsedTime.label(t1)
  end
end
