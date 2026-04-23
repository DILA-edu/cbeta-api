namespace :zip do  
  desc "zip docx 一經一檔"
  task :docx => :environment do
    t1 = Time.now
    ZipDocx.new.zip
    puts ElapsedTime.label(t1)
  end
end

class ZipDocx
  def zip
    folder = Rails.root.join("public", "download", "docx")
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
      work_path.glob("*.docx").each do |docx_path|
        basename = docx_path.basename
        zip_path = File.join(work, basename)
        zipfile.add(zip_path, docx_path)
      end
    end
  end
end
