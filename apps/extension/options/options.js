/**
 * FocusGuard Browser Extension — Options & Local Policy Inspector
 */

document.addEventListener('DOMContentLoaded', async () => {
  const container = document.getElementById('policies-container');

  async function loadPolicies() {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      chrome.storage.local.get(['fg_policies', 'fg_policy_version'], (items) => {
        const policies = items.fg_policies || [];
        if (policies.length === 0) {
          container.innerHTML = `<div style="color: #94a3b8; font-size: 13px;">No local policies installed. Synchronizing with cloud...</div>`;
          return;
        }

        container.innerHTML = '';
        policies.forEach(p => {
          const item = document.createElement('div');
          item.className = 'policy-item';
          const targetStr = (p.targets || []).map(t => `${t.targetType}: ${t.targetValue}`).join(', ') || 'All Sites';
          item.innerHTML = `
            <div>
              <div style="font-weight: 700; margin-bottom: 4px;">${p.name} (v${p.version || 1})</div>
              <div style="font-size: 12px; color: #94a3b8;">${targetStr} &bull; Mode: ${p.enforcementMode || 'BLOCK'}</div>
            </div>
            <span class="badge-pill">${p.isEnabled !== false ? 'ENFORCING' : 'DISABLED'}</span>
          `;
          container.appendChild(item);
        });
      });
    }
  }

  loadPolicies();

  document.getElementById('btn-sync-now').addEventListener('click', async () => {
    try {
      const resp = await fetch('http://localhost:8080/api/v1/policies');
      if (resp.ok) {
        const policies = await resp.json();
        if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
          chrome.storage.local.set({ fg_policies: policies.policies || policies, fg_policy_version: 2 }, () => {
            alert('Policies successfully synchronized!');
            loadPolicies();
          });
        }
      }
    } catch (e) {
      alert('Cloud server unreachable. Operating in offline cached mode.');
    }
  });

  document.getElementById('btn-open-web').addEventListener('click', () => {
    window.open('http://localhost:3000', '_blank');
  });
});
