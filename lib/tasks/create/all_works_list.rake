namespace :create do
  desc "產生 全部佛典 卷列表"
  task :all_works_list => :environment do
    CreateAllWorksList.new.create
  end
end

class CreateAllWorksList
  def create
    t1 = Time.now
    puts "read model Work"
    r = []
    Work.order(:sort_order).each do |w|
      h = {
        work: w.n,
        title: w.title
      }
      if w.juan_list.nil?
        if not w.juan.nil? and w.juan > 1
          h[:juans] = (1..w.juan).to_a
        end
      else
        h[:juans] = w.juan_list.split(',')
      end
      r << h
    end

    fn = File.join(Rails.configuration.cb.dl, 'all-works.json')
    puts "write #{fn}"
    File.write(fn, JSON.pretty_generate(r))
    puts "花費時間: #{ChronicDuration.output((Time.now - t1).round)}"
  end
end
