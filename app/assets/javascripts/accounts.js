// 撤銷 API key 前的確認對話框。
//
// 本專案沒有 rails-ujs / Turbo，而且 CSP 的 script-src 沒有 'unsafe-inline'，
// 不能用 inline onsubmit，所以在這裡替 form[data-confirm] 掛 listener。
document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('form[data-confirm]').forEach(function (form) {
    form.addEventListener('submit', function (event) {
      if (!window.confirm(form.dataset.confirm)) {
        event.preventDefault();
      }
    });
  });
});
