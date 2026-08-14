/**
 * FocusGuard Browser Extension — Block Page Interactive Logic
 */

document.addEventListener('DOMContentLoaded', () => {
  const urlParams = new URLSearchParams(window.location.search);
  const target = urlParams.get('target') || 'Restricted Site';
  const reason = urlParams.get('reason') || 'Daily attention budget reached.';
  const policy = urlParams.get('policy') || 'Attention Budget';
  const used = urlParams.get('used') || '30';
  const limit = urlParams.get('limit') || '30';
  const reset = urlParams.get('reset') || '12:00 AM';

  document.getElementById('blocked-target').textContent = target;
  document.getElementById('block-reason').textContent = reason;
  document.getElementById('policy-scope').textContent = policy;
  document.getElementById('budget-ratio').textContent = `${used} / ${limit} minutes`;
  document.getElementById('next-reset').textContent = reset;

  document.getElementById('btn-return-focus').addEventListener('click', () => {
    // Navigate away or close current tab
    if (typeof chrome !== 'undefined' && chrome.tabs && chrome.tabs.getCurrent) {
      chrome.tabs.getCurrent((tab) => {
        if (tab && tab.id) {
          chrome.tabs.remove(tab.id);
        } else {
          window.location.href = 'about:blank';
        }
      });
    } else {
      window.location.href = 'about:blank';
    }
  });

  document.getElementById('btn-view-policy').addEventListener('click', () => {
    if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.openOptionsPage) {
      chrome.runtime.openOptionsPage();
    } else {
      alert(`Active Policy: ${policy}\nTarget: ${target}\nLimit: ${limit} minutes/day\nReset: ${reset}`);
    }
  });
});
