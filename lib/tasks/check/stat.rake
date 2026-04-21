require 'cbeta_p5a_share'

namespace :check do
  task :stat => :environment do
    CheckStat.new.check
  end
end

class CheckStat
  def initialize
    @xml_root = Pathname.new(Rails.configuration.cbeta_xml)
    @base = Rails.root.join('public', 'download', 'stat')
    read_cats
    read_vols
    read_works
  end

  def check
    check_cats
    check_T0220
    check_vols
  end

  private

  # 檢查 分部類 vs. 分部 字數是否相符
  def check_cats
    puts "check_cats"
    cats2 = Hash.new(0)
    @works.each_value do |w|
      next if w[:cats].nil?
      w[:cats].split(',') do |cat|
        cats2[cat] += w[:cjk_chars]
      end
    end

    @cats.each do |k, v1|
      v2 = cats2[k]
      unless v1 == v2
        abort <<~TXT
          [#{__LINE__}] 部類字數不符: #{k}
          根據部類字數統計: #{v1}
          根據分部字數統計: #{v2}
          差距: #{(v1-v2).abs}
        TXT
      end
    end
  end

  def check_T0220
    puts "check_T0220"
    i1 = @works['T0220'][:cjk_chars]
    i2 = %w[T05 T06 T07].sum { @vols[it] }
    abort "[#{__LINE__}] T0220 字數不符" unless i1 == i2
  end

  # 檢查 分冊 vs. 分部 字數是否符合
  def check_vols
    puts "check_vols"
    @xml_root.each_child do |canon_pn|
      canon = canon_pn.basename.to_s
      next unless canon.size < 3
      canon_pn.each_child do |vol_pn|
        check_vols_vol(vol_pn)
      end
    end
    puts
  end

  def check_vols_vol(vol_pn)
    vol = vol_pn.basename.to_s
    return if vol.start_with?('.')

    i = 0
    vol_pn.each_child do |xml_pn|
      bn = xml_pn.basename('.*').to_s
      work_id = CBETA.get_work_id_from_file_basename(bn)
      w = Work.find_by(n: work_id)
      return if w.vol.include?('..') # 如果跨冊 就整冊跳過
      i += @works[work_id][:cjk_chars]
    end

    print "\rcheck vol: #{vol}  "
    abort "分冊字數統計不符: #{vol}" unless i == @vols[vol]
  end

  def read_cats
    @cats = {}
    path = File.join(@base, 'cbeta-word-count-cat.csv')
    puts "read #{path}"
    CSV.foreach(path, headers: true) do |row|
      k = row['category']
      @cats[k] = row['cjk_chars'].to_i
    end
  end

  def read_vols
    @vols = {}
    path = File.join(@base, 'cbeta-word-count-vol.csv')
    puts "read #{path}"
    CSV.foreach(path, headers: true) do |row|
      k = row['vol']
      @vols[k] = row['cjk_chars'].to_i
    end
  end

  def read_works
    @works = {}
    path = File.join(@base, 'cbeta-word-count.csv')
    puts "read #{path}"
    CSV.foreach(path, headers: true) do |row|
      k = row['work']
      @works[k] = { 
        cjk_chars: row['cjk_chars'].to_i,
        cats: row['category']
      }
    end
  end
  include CbetaP5aShare
end
