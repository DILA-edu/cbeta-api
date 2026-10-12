# frozen_string_literal: true

namespace :check do
  desc '比對 xml4docx 與轉出的 docx, 例: rake check:docx[T01,8]'
  task :docx, %i[filter workers] => :environment do |_t, args|
    t1 = Time.now
    failures = DocxBatchChecker.new(filter: args[:filter], workers: args[:workers]).check
    puts ElapsedTime.label(t1)
    exit 1 if failures.positive?
  end
end
