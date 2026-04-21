namespace :create do
  desc "產生 嘉興藏檢查表"
  task :check_list_j => :environment do
    CreateCheckListJ.new.create
  end
end

class CreateCheckListJ
  def create
    t1 = Time.now
    puts "read from model Work"
    works = Work.where('n like ?', "J%").order(:n)
    fn = File.join(Rails.configuration.cb.dl, 'check-list-J.csv')
    puts "write #{fn}"
    
    CSV.open(fn, "wb") do |csv|
      csv << ["經號", "經名", "卷次"]
      works.each do |w|
        abort "Work n: #{w.n}, juan: nil" if w.juan.nil?
        (1..w.juan).each do |j|
          csv << [w.n, w.title, "卷#{j}"]
        end
      end
    end

    puts "花費時間: #{ChronicDuration.output((Time.now - t1).round)}"
  end
end
