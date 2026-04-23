namespace :zip do  
  desc "zip odt 一經一檔"
  task :odt => :environment do
    t1 = Time.now
    ZipOdt.new.zip
    puts ElapsedTime.label(t1)
  end
end

class ZipOdt
  def zip
    folder = Rails.root.join("public", "download", "odt")
    folder.each_child do |child|
      next unless child.directory?
      zip_canon(child)
    end
  end

  private

  def zip_canon(canon_path)
    @canon_path = canon_path
    canon_path.each_child do |child|
      next unless child.directory?
      zip_work(child)
    end
  end

  def zip_work(work_path)
    work = work_path.basename(".*")
    dest_zip_path = @canon_path.join("#{work}.zip")
    puts dest_zip_path

    Zip::File.open(dest_zip_path, create: true) do |zipfile|
      work_path.glob("*.odt").each do |odt_path|
        basename = odt_path.basename
        zip_path = File.join(work, basename)
        zipfile.add(zip_path, odt_path)
      end
    end
  end
end
