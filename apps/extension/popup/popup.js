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

  // Query background service worker for live device and network status
  if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.sendMessage) {
    chrome.runtime.sendMessage({ type: 'GET_STATUS' }, (status) => {
      if (status) {
        const netBadge = document.getElementById('net-badge');
        if (netBadge) {
          netBadge.textContent = status.networkState || 'ONLINE';
          if (status.networkState === 'ONLINE') {
            netBadge.style.color = '#34d399';
            netBadge.style.borderColor = 'rgba(16, 185, 129, 0.3)';
          } else if (status.networkState === 'RECONNECTING' || status.networkState === 'SYNCING') {
            netBadge.style.color = '#38bdf8';
            netBadge.style.borderColor = 'rgba(56, 189, 248, 0.3)';
          } else {
            netBadge.style.color = '#f59e0b';
            netBadge.style.borderColor = 'rgba(245, 158, 11, 0.3)';
          }
        }

        const devDisplay = document.getElementById('device-id-display');
        if (devDisplay) {
          const rawId = status.deviceId || 'ext_node';
          const shortId = rawId.length > 18 ? rawId.substring(0, 16) + '...' : rawId;
          devDisplay.textContent = `ID: ${shortId}`;
        }

        const pairingBadge = document.getElementById('pairing-badge');
        const pairingForm = document.getElementById('pairing-form');
        const isPaired = status.pairingStatus === 'PAIRED';

        if (pairingBadge) {
          pairingBadge.textContent = isPaired ? 'PAIRED' : 'UNPAIRED';
          pairingBadge.style.color = isPaired ? '#34d399' : '#f59e0b';
        }

        if (pairingForm) {
          pairingForm.style.display = isPaired ? 'none' : 'block';
        }

        // Focus session status
        const focus = status.focusSession;
        if (focus && focus.isActive) {
          document.getElementById('focus-badge').textContent = 'LOCKDOWN';
          document.getElementById('focus-badge').style.background = 'rgba(239, 68, 68, 0.2)';
          document.getElementById('focus-badge').style.color = '#f87171';
          document.getElementById('focus-desc').textContent = `${focus.name || 'Remote Focus'} is active (${focus.durationMinutes || 45}m). Distracting sites are blocked.`;
        }
      }
    });
  }

  // Handle Pairing Form Submission
  const btnSubmitPair = document.getElementById('btn-submit-pair');
  if (btnSubmitPair) {
    btnSubmitPair.addEventListener('click', () => {
      const codeInput = document.getElementById('input-pairing-code');
      const msgEl = document.getElementById('pairing-msg');
      const code = (codeInput ? codeInput.value : '').trim();

      if (!code) {
        if (msgEl) {
          msgEl.style.display = 'block';
          msgEl.style.color = '#f87171';
          msgEl.textContent = 'Please enter a 6-character pairing code';
        }
        return;
      }

      btnSubmitPair.disabled = true;
      btnSubmitPair.textContent = 'Linking...';
      if (msgEl) {
        msgEl.style.display = 'block';
        msgEl.style.color = '#38bdf8';
        msgEl.textContent = 'Submitting request. Approve in your dashboard...';
      }

      chrome.runtime.sendMessage({ type: 'SUBMIT_PAIRING_CODE', code: code }, (resp) => {
        btnSubmitPair.disabled = false;
        btnSubmitPair.textContent = 'Pair';

        if (resp && resp.success) {
          if (msgEl) {
            msgEl.style.color = '#34d399';
            msgEl.textContent = '✓ Device paired successfully!';
          }
          setTimeout(() => { window.location.reload(); }, 1200);
        } else {
          if (msgEl) {
            msgEl.style.color = '#f87171';
            msgEl.textContent = resp?.error || 'Pairing failed. Check code & try again.';
          }
        }
      });
    });
  }

  document.getElementById('btn-open-dashboard').addEventListener('click', () => {
    const dashboardUrl = 'http://localhost:3001';
    if (typeof chrome !== 'undefined' && chrome.tabs) {
      chrome.tabs.create({ url: dashboardUrl });
    } else {
      window.open(dashboardUrl, '_blank');
    }
  });
});

