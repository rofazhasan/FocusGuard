/**
 * FocusGuard Browser Extension — Popup Logic
 */

document.addEventListener('DOMContentLoaded', async () => {
  // Query active tab
  if (typeof chrome !== 'undefined' && chrome.tabs && chrome.tabs.query) {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs && tabs[0] && tabs[0].url) {
        try {
          const url = new URL(tabs[0].url);
          const domain = url.hostname.replace(/^www\./, '');
          document.getElementById('current-domain').textContent = domain;
        } catch (e) {
          document.getElementById('current-domain').textContent = 'New Tab / Internal';
        }
      }
    });
  }

  // Load storage state
  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    chrome.storage.local.get(['fg_today_usage', 'fg_focus_session'], (items) => {
      const focus = items.fg_focus_session;
      if (focus && focus.isActive) {
        document.getElementById('focus-badge').textContent = 'LOCKDOWN';
        document.getElementById('focus-badge').style.background = 'rgba(239, 68, 68, 0.2)';
        document.getElementById('focus-badge').style.color = '#f87171';
        document.getElementById('focus-desc').textContent = `${focus.name || 'Remote Focus'} is active (${focus.durationMinutes || 45}m). Distracting sites are blocked.`;
      }
    });
  }

  document.getElementById('btn-open-dashboard').addEventListener('click', () => {
    if (typeof chrome !== 'undefined' && chrome.tabs) {
      chrome.tabs.create({ url: 'http://localhost:3000' });
    } else {
      window.open('http://localhost:3000', '_blank');
    }
  });
});
