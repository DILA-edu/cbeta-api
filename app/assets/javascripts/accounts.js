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

// 「複製」按鈕：把 data-copy-target 指到的元素文字複製到剪貼簿。
// 同樣因為 CSP 不允許 inline handler，在這裡掛 listener。
document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('[data-copy-target]').forEach(function (button) {
    var target = document.getElementById(button.dataset.copyTarget);
    if (!target) return;

    button.addEventListener('click', function () {
      copyText(target.textContent.trim()).then(function () {
        flashLabel(button, button.dataset.copiedLabel || '已複製', true);
      }).catch(function () {
        flashLabel(button, '複製失敗，請手動選取', false);
      });
    });
  });

  // navigator.clipboard 只在 secure context (https / localhost) 可用，
  // 其他情況退回 textarea + execCommand。
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).catch(function () {
        return legacyCopy(text);
      });
    }

    return legacyCopy(text);
  }

  function legacyCopy(text) {
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();

    var copied = false;
    try {
      copied = document.execCommand('copy');
    } finally {
      document.body.removeChild(textarea);
    }
    return copied ? Promise.resolve() : Promise.reject();
  }

  // 按鈕文字暫時換成結果訊息，兩秒後還原。
  function flashLabel(button, label, success) {
    if (button.dataset.copyTimer) return;

    var original = button.textContent.trim();
    var stateClass = success ? 'btn-success' : 'btn-danger';
    button.textContent = label;
    button.classList.remove('btn-outline-secondary');
    button.classList.add(stateClass);

    button.dataset.copyTimer = window.setTimeout(function () {
      button.textContent = original;
      button.classList.remove(stateClass);
      button.classList.add('btn-outline-secondary');
      delete button.dataset.copyTimer;
    }, 2000);
  }
});
