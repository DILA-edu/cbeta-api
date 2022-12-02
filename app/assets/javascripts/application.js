// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or any plugin's vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require jquery3
//= require jquery_ujs
//= require popper
//= require bootstrap	
// require turbolinks
//= require_tree .

function report_init_datepicker() {
  $( '#d1, #d2' ).datepicker();
  $( '#d1, #d2' ).datepicker("option", "dateFormat", "yy-mm-dd" );

  // 取得 request url 裡的參數
  const params = new Proxy(new URLSearchParams(window.location.search), {
    get: (searchParams, prop) => searchParams.get(prop),
  });

  // 如果沒有指定日期參數，就使用今天的日期
  d1 = params.d1 || new Date()
  d2 = params.d2 || new Date()

  // 設定 日期 預設值
  $( '#d1' ).datepicker("setDate", d1 );
  $( '#d2' ).datepicker("setDate", d2 );
}
