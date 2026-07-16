require 'csv'
require 'my_cbeta_share'

# 一次性 migration:
# 把 data-static/layers 的 position 由「舊字位制」換算為「新字位制」。
#
#   舊制: 「□」「▆」「○」等被當標點剝除,不佔字位 (資料 2021~2025-04 產生)
#   新制: 依 CBETA 2025-07-24 決議,「□」「▆」視為一般文字佔字位;
#         實測 cbeta gem 的 span.t w 屬性亦把「○」計入,故一併對齊
#         (規則以 CbetaString 為準)。
#
# 用法:
#   bin/rails 'import:migrate_layers_puncs'        # dry-run,只報告不寫檔
#   bin/rails 'import:migrate_layers_puncs[apply]' # 實際寫回 CSV
namespace :import do
  # 舊制標點規則 (即 migration 前 layers.rake 內建的 PUNCS)
  OLD_PUNCS = /[\n\r,.()\[\]\x20。．，、；？！：（）「」『』《》＜＞〈〉〔〕［］【】〖〗…—　▆■□○―→←△]/

  task :migrate_layers_puncs, [:apply] => :environment do |t, args|
    apply = (args[:apply] == 'apply')
    layers_dir = Rails.root.join('data-static', 'layers')
    xml_base = Rails.application.config.cbeta_xml
    gaijis = MyCbetaShare.get_cbeta_gaiji
    cs = CbetaString.new

    stats = { files: 0, rows: 0, changed: 0, unchanged: 0,
              skipped_f: 0, errors: 0, name_mismatch: 0 }
    errors = []
    mismatches = []
    raw_cache = {}

    csv_files = Dir.glob(File.join(layers_dir, '**', '*.csv')).sort

    csv_files.each do |fn|
      stats[:files] += 1
      # .../layers/<layer>/<canon>/<vol>/<base>.csv
      rel = Pathname.new(fn).relative_path_from(layers_dir).to_s
      parts = rel.split('/')                 # [layer, canon, vol, base.csv]
      canon = parts[1]
      vol   = parts[2]
      base  = File.basename(fn, '.csv')
      xml   = File.join(xml_base, canon, vol, "#{base}.xml")

      unless File.exist?(xml)
        errors << "XML 不存在: #{xml} (csv: #{rel})"
        stats[:errors] += 1
        next
      end
      raw_lines = (raw_cache[xml] ||= CbetaLineReader.new(gaijis).read(xml))

      rows = CSV.read(fn, headers: true)
      changed_in_file = false

      rows.each do |row|
        stats[:rows] += 1
        lb = row['lb']
        old_pos = row['position'].to_i
        name = row['name']
        type = row['type']

        # footnote 行,runtime 亦跳過,不動
        if lb.start_with?('f')
          stats[:skipped_f] += 1
          next
        end

        raw = raw_lines[lb]
        if raw.nil?
          errors << "#{rel} lb=#{lb} 在 XML 找不到該行"
          stats[:errors] += 1
          next
        end

        # 逐字走原始行,同時累計舊制/新制字位,找到舊制第 old_pos 個字
        old_rank = 0
        new_rank = 0
        new_pos = nil
        target = nil
        raw.each_char do |ch|
          ok = !ch.match?(OLD_PUNCS)
          nk = !cs.punc?(ch)
          old_rank += 1 if ok
          new_rank += 1 if nk
          if ok && old_rank == old_pos
            new_pos = new_rank
            target = ch
            break
          end
        end

        if new_pos.nil?
          errors << "#{rel} lb=#{lb} position=#{old_pos} 超出行字數 (#{name})"
          stats[:errors] += 1
          next
        end

        # sanity: 舊制下該字位邊界字元是否符合名稱 (start→首字, end→末字)
        expected = (type == 'end') ? name[-1] : name[0]
        if target != expected
          mismatches << "#{rel} lb=#{lb} pos=#{old_pos} #{type} 名稱=#{name} 期望「#{expected}」實得「#{target}」"
          stats[:name_mismatch] += 1
        end

        if new_pos != old_pos
          row['position'] = new_pos.to_s
          stats[:changed] += 1
          changed_in_file = true
        else
          stats[:unchanged] += 1
        end
      end

      if apply && changed_in_file
        CSV.open(fn, 'w') do |csv|
          csv << rows.headers
          rows.each { |r| csv << r.fields }
        end
      end
    end

    puts '=' * 60
    puts "模式: #{apply ? '實際寫回 (apply)' : 'DRY-RUN (未寫檔)'}"
    puts "CSV 檔數: #{stats[:files]}"
    puts "資料列數: #{stats[:rows]}"
    puts "position 變更: #{stats[:changed]}"
    puts "position 不變: #{stats[:unchanged]}"
    puts "跳過(footnote): #{stats[:skipped_f]}"
    puts "錯誤: #{stats[:errors]}"
    puts "舊制名稱邊界不符(需檢視): #{stats[:name_mismatch]}"

    unless errors.empty?
      puts "\n---- 錯誤 (前 30) ----"
      errors.first(30).each { |e| puts e }
    end
    unless mismatches.empty?
      puts "\n---- 名稱邊界不符 (前 30) ----"
      mismatches.first(30).each { |m| puts m }
    end
    puts '=' * 60
    puts '這是 DRY-RUN,如要寫回請執行: rake "import:migrate_layers_puncs[apply]"' unless apply
  end
end
