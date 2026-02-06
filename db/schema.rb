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

ActiveRecord::Schema[8.1].define(version: 2026_02_06_090000) do
  create_table "canons", force: :cascade do |t|
    t.integer "children_count"
    t.string "id2"
    t.string "name"
    t.string "uuid"
    t.index ["id2"], name: "index_canons_on_id2", unique: true
    t.index ["uuid"], name: "index_canons_on_uuid", unique: true
  end

  create_table "catalog_entries", force: :cascade do |t|
    t.string "file"
    t.integer "juan_end"
    t.integer "juan_start"
    t.string "label"
    t.string "lb"
    t.string "n"
    t.string "node_type"
    t.string "parent"
    t.integer "sort"
    t.string "work"
    t.index ["parent", "n"], name: "index_catalog_entries_on_parent_and_n"
    t.index ["parent", "sort"], name: "index_catalog_entries_on_parent_and_sort"
  end

  create_table "categories", force: :cascade do |t|
    t.integer "n"
    t.string "name"
    t.index ["n"], name: "index_categories_on_n"
    t.index ["name"], name: "index_categories_on_name"
  end

  create_table "gaijis", force: :cascade do |t|
    t.string "cb"
    t.string "pua"
    t.string "zzs"
    t.index ["cb"], name: "index_gaijis_on_cb"
    t.index ["pua"], name: "index_gaijis_on_pua"
    t.index ["zzs"], name: "index_gaijis_on_zzs"
  end

  create_table "goto_abbrs", force: :cascade do |t|
    t.string "abbr"
    t.string "ref"
    t.index ["abbr"], name: "index_goto_abbrs_on_abbr"
  end

  create_table "juan_lines", force: :cascade do |t|
    t.string "content_uuid"
    t.integer "juan"
    t.string "lb"
    t.string "lb_end"
    t.string "uuid"
    t.string "vol"
    t.string "work"
    t.index ["uuid"], name: "index_juan_lines_on_uuid", unique: true
    t.index ["vol", "lb"], name: "index_juan_lines_on_vol_and_lb", unique: true
    t.index ["work", "juan"], name: "index_juan_lines_on_work_and_juan"
  end

  create_table "lb_maps", force: :cascade do |t|
    t.string "lb1"
    t.string "lb2"
    t.index ["lb1"], name: "index_lb_maps_on_lb1"
    t.index ["lb2"], name: "index_lb_maps_on_lb2"
  end

  create_table "lines", id: :integer, default: nil, force: :cascade do |t|
    t.string "col"
    t.text "html"
    t.integer "juan"
    t.string "line"
    t.string "linehead"
    t.text "notes"
    t.string "page"
    t.integer "ser_no"
    t.string "vol"
    t.string "work"
    t.index ["linehead"], name: "index_lines_on_edition_and_linehead"
    t.index ["ser_no"], name: "index_lines_on_ser_no"
    t.index ["vol", "page", "col", "line"], name: "index_lines_on_vol_and_page_and_col_and_line"
    t.index ["work", "juan", "ser_no"], name: "index_lines_on_work_and_juan_and_ser_no"
  end

  create_table "people", force: :cascade do |t|
    t.string "id2", null: false
    t.string "name"
    t.index ["id2"], name: "index_people_on_id2", unique: true
    t.index ["name"], name: "index_people_on_name"
  end

  create_table "places", force: :cascade do |t|
    t.string "auth_id"
    t.float "latitude"
    t.float "longitude"
    t.string "name"
    t.index ["auth_id"], name: "index_places_on_auth_id", unique: true
  end

  create_table "places_works", id: false, force: :cascade do |t|
    t.integer "place_id", null: false
    t.integer "work_id", null: false
  end

  create_table "terms", force: :cascade do |t|
    t.text "synonyms"
    t.string "term"
    t.index ["term"], name: "index_terms_on_term"
  end

  create_table "toc_nodes", id: :integer, default: nil, force: :cascade do |t|
    t.string "canon"
    t.string "file"
    t.integer "juan"
    t.string "label"
    t.string "lb"
    t.string "n"
    t.string "parent"
    t.string "sort_order"
    t.string "work"
    t.index ["canon"], name: "index_toc_nodes_on_canon"
    t.index ["n"], name: "index_toc_nodes_on_n"
    t.index ["parent", "n"], name: "index_toc_nodes_on_parent_and_n"
    t.index ["sort_order"], name: "index_toc_nodes_on_sort_order"
  end

  create_table "variants", force: :cascade do |t|
    t.string "k"
    t.string "vars"
    t.index ["k"], name: "index_variants_on_k"
  end

  create_table "works", id: :integer, default: nil, force: :cascade do |t|
    t.string "alt"
    t.string "byline"
    t.string "canon"
    t.string "category"
    t.string "category_ids"
    t.integer "chars"
    t.integer "cjk_chars"
    t.text "creators"
    t.text "creators_with_id"
    t.integer "en_words"
    t.integer "juan"
    t.text "juan_list"
    t.integer "juan_start"
    t.string "n"
    t.string "orig_category"
    t.string "sort_order"
    t.string "time_dynasty"
    t.integer "time_from"
    t.integer "time_to"
    t.string "title"
    t.string "uuid"
    t.string "vol"
    t.string "work_type"
    t.index ["canon"], name: "index_works_on_canon"
    t.index ["n"], name: "index_works_on_n"
    t.index ["sort_order"], name: "index_works_on_sort_order"
    t.index ["uuid"], name: "index_works_on_uuid", unique: true
  end

  create_table "xml_files", force: :cascade do |t|
    t.string "file"
    t.integer "juan_start"
    t.integer "juans"
    t.string "vol"
    t.string "work"
    t.index ["vol", "file"], name: "index_xml_files_on_vol_and_file"
    t.index ["work", "file"], name: "index_xml_files_on_work_and_file"
    t.index ["work", "vol"], name: "index_xml_files_on_work_and_vol"
  end
end
