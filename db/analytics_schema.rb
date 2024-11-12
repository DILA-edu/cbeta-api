# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2022_09_23_035010) do
  create_table "visits", force: :cascade do |t|
    t.string "url"
    t.date "accessed_at"
    t.integer "count"
    t.string "referer"
    t.index ["url", "accessed_at"], name: "index_visits_on_url_and_accessed_at"
    t.index ["url", "referer", "accessed_at"], name: "index_visits_on_url_and_referer_and_accessed_at"
  end

end
