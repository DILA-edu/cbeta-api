Rails.application.routes.draw do
  root 'static_pages#home'
  match 'catalog_entry', to: 'catalog_entry#index', via: [:get, :post]

  match 'api/collections', to: 'canons#index', via: [:get, :post]
  match '/api/collections/:uuid/resources', to: 'works#index', via: [:get, :post]
  match '/api/resources/:uuid/sections', 
        to: 'juans#list_for_asia_network', 
        via: [:get, :post]
  match '/api/sections/:uuid/content_units', 
        to: 'juans#content_for_asia_network', 
        via: [:get, :post]
  match '/api/sections/:uuid', to: 'juans#show_for_asia_network', via: [:get, :post]

  match 'category/:category', to: 'juans#index', via: [:get, :post]
  match 'chinese_tools/sc2tc', via: [:get, :post]

  match 'export/all_creators2', via: [:get, :post]
  match 'export/all_creators', via: [:get, :post]
  match 'export/all_works', via: [:get, :post]
  match 'export/check_list', via: [:get, :post]
  match 'export/creator_strokes', via: [:get, :post]
  match 'export/creator_strokes_works', via: [:get, :post]
  match 'export/dynasty_works', via: [:get, :post]
  match 'export/dynasty', via: [:get, :post]
  match 'export/scope_selector_by_category', via: [:get, :post]
  match 'export/scope_selector_by_vol', via: [:get, :post]

  match 'juans/goto', via: [:get, :post]
  match 'juans', to: 'juans#index', via: [:get, :post]

  match 'kwic3/juan', to: 'kwic3#juan', via: [:get, :post]
  match 'kwic3',      to: 'kwic3#index', via: [:get, :post]
  
  match 'lines', to: 'lines#index', via: [:get, :post]
  
  get 'report/access'
  get 'report/daily', to: 'report#daily'
  match 'report/url', to: 'report#url', as: :report_url, via: [:get, :post]

  match 'sphinx/all_in_one', via: [:get, :post]
  match 'sphinx/facet/:facet_by', to: 'sphinx#facet', via: [:get, :post]
  match 'sphinx/footnotes', to: 'sphinx#notes', defaults: { note_place: 'foot' }, via: [:get, :post]
  match 'sphinx/extended',  via: [:get, :post]
  match 'sphinx/notes',     via: [:get, :post]
  match 'sphinx/sc',        via: [:get, :post]
  match 'sphinx/synonym',   via: [:get, :post]
  match 'sphinx/title',     via: [:get, :post]
  match 'sphinx/variants',  via: [:get, :post]
  match 'sphinx', to: 'sphinx#index', via: [:get, :post]

  get 'static_pages/catalog'
  get 'static_pages/callback'
  get 'static_pages/category'
  get 'static_pages/creators'
  get 'static_pages/download_docusky'
  get 'static_pages/download_ebooks'
  get 'static_pages/download_footnotes'
  get 'static_pages/download_html'
  get 'static_pages/download_text'
  get 'static_pages/get_html'
  get 'static_pages/goto'
  get 'static_pages/html_for_ui'
  get 'static_pages/kwic3_juan'
  get 'static_pages/kwic3'
  get 'static_pages/line'
  get 'static_pages/log'
  get 'static_pages/log_old'
  get 'static_pages/rise_shine'
  get 'static_pages/sc2tc'
  get 'static_pages/scope_selector'
  get 'static_pages/sphinx_all_in_one'
  get 'static_pages/sphinx_extended'
  get 'static_pages/sphinx_facet'
  get 'static_pages/sphinx_filter'
  get 'static_pages/sphinx_footnotes'
  get 'static_pages/sphinx_notes'
  get 'static_pages/sphinx_sc'
  get 'static_pages/sphinx_synonym'
  get 'static_pages/sphinx_title'
  get 'static_pages/sphinx_vars'
  get 'static_pages/sphinx'
  get 'static_pages/time'
  get 'static_pages/toc_search'
  get 'static_pages/toc'
  get 'static_pages/word_seg'
  get 'static_pages/works'
  get 'static_pages/work'

  match 'toc', to: 'toc_node#index', via: [:get, :post]

  match 'word_seg2', to: 'word_seg#run', via: [:get, :post]
  match 'word_seg', to: 'word_seg#index', via: [:get, :post]

  match 'work/:work_id/juan/:juan/edition/:ed', to: 'juans#edition', via: [:get, :post]
  match 'works/word_count', via: [:get, :post]
  match 'works', to: 'works#index', via: [:get, :post]

  #match ':controller', action: 'index', via: [:get, :post]
end