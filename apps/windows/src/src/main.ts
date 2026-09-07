/**
 * FocusGuard Windows Desktop UI Bootstrap
 * Modern client router, dynamic telemetry binders, and policy controllers.
 */

interface ApplicationItem {
  executableName: string;
  displayName: string;
  isTracked: boolean;
}

interface PolicyItem {
  name: string;
  limitMinutes: number;
  warnMinutes: number;
  action: string;
  targetExecutable: string;
}

class FocusGuardApp {
  private currentTab = 'dashboard';
  private trackingSeconds = 860; // 14m 20s initial
  private dailyLimitSeconds = 1800; // 30m

  constructor() {
    this.initNavigation();
    this.initPolicyForm();
    this.initSyncButton();
    this.initDiagnosticsExport();
    this.startLiveTelemetry();
  }

  private initNavigation() {
    const navButtons = document.querySelectorAll<HTMLButtonElement>('.nav-item');
    navButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const tab = btn.dataset.tab;
        if (tab) {
          this.switchTab(tab);
        }
      });
    });
  }

  private switchTab(tabId: string) {
    this.currentTab = tabId;

    // Update nav buttons
    document.querySelectorAll('.nav-item').forEach(btn => {
      btn.classList.toggle('active', (btn as HTMLElement).dataset.tab === tabId);
    });

    // Update section visibility
    document.querySelectorAll('.tab-content').forEach(section => {
      section.classList.toggle('hidden', section.id !== `tab-${tabId}`);
    });

    // Update title
    const titles: Record<string, { title: string; subtitle: string }> = {
      dashboard: { title: 'Dashboard', subtitle: 'Real-time Windows process focus and attention telemetry' },
      applications: { title: 'Applications', subtitle: 'Discovered desktop processes and tracking controls' },
      policies: { title: 'Policies', subtitle: 'Daily time budgets, warning thresholds, and safe actions' },
      usage: { title: 'Usage Analytics', subtitle: 'Historical process engagement and session timelines' },
      settings: { title: 'Settings', subtitle: 'Startup configuration, idle threshold, and cloud sync cadence' },
      diagnostics: { title: 'Diagnostics', subtitle: 'System health, SQLite WAL state, and masked telemetry logs' },
    };

    const header = titles[tabId] || titles.dashboard;
    const titleEl = document.getElementById('page-title');
    const subEl = document.getElementById('page-subtitle');
    if (titleEl) titleEl.textContent = header.title;
    if (subEl) subEl.textContent = header.subtitle;
  }

  private initPolicyForm() {
    const targetInput = document.getElementById('pol-target') as HTMLInputElement;
    const limitInput = document.getElementById('pol-limit') as HTMLInputElement;
    const warnInput = document.getElementById('pol-warn') as HTMLInputElement;
    const actionSelect = document.getElementById('pol-action') as HTMLSelectElement;
    const previewEl = document.getElementById('policy-preview-text');
    const saveBtn = document.getElementById('btn-save-policy');

    const updatePreview = () => {
      const target = targetInput?.value.trim() || 'Target application';
      const limit = limitInput?.value || '30';
      const warn = warnInput?.value || '25';
      const action = actionSelect?.value || 'CLOSE_APPLICATION';

      if (previewEl) {
        previewEl.textContent = `${target} will warn you at ${warn} minutes and enforce ${action} at ${limit} minutes.`;
      }
    };

    targetInput?.addEventListener('input', updatePreview);
    limitInput?.addEventListener('input', updatePreview);
    warnInput?.addEventListener('input', updatePreview);
    actionSelect?.addEventListener('change', updatePreview);

    saveBtn?.addEventListener('click', () => {
      const target = targetInput?.value.trim();
      if (!target) {
        alert('Please specify a target executable (e.g. discord.exe)');
        return;
      }

      this.dailyLimitSeconds = parseInt(limitInput.value, 10) * 60;
      alert(`Policy for ${target} saved successfully.`);
      this.switchTab('dashboard');
    });
  }

  private initSyncButton() {
    const syncBtn = document.getElementById('btn-sync-now');
    syncBtn?.addEventListener('click', () => {
      syncBtn.classList.add('loading');
      syncBtn.querySelector('span')!.textContent = 'Syncing...';

      setTimeout(() => {
        syncBtn.classList.remove('loading');
        syncBtn.querySelector('span')!.textContent = 'Synced';
        setTimeout(() => {
          syncBtn.querySelector('span')!.textContent = 'Sync Cloud';
        }, 2000);
      }, 800);
    });
  }

  private initDiagnosticsExport() {
    const exportBtn = document.getElementById('btn-export-diag');
    exportBtn?.addEventListener('click', () => {
      const diagData = {
        appVersion: '0.3.0',
        platform: 'Windows 11 Pro (x86_64)',
        deviceIdMasked: 'e98abefa...a62f',
        policyVersion: 1,
        activeTrackingState: 'TRACKING',
        idleThresholdSec: 60,
        pendingEvents: 0,
        sqliteHealth: 'OK',
        exportedAt: new Date().toISOString()
      };

      const blob = new Blob([JSON.stringify(diagData, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `focusguard-diagnostics-${Date.now()}.json`;
      a.click();
      URL.revokeObjectURL(url);
    });
  }

  private startLiveTelemetry() {
    // 1-second live ticker simulating foreground window timer
    setInterval(() => {
      this.trackingSeconds += 1;
      const mins = Math.floor(this.trackingSeconds / 60);
      const secs = this.trackingSeconds % 60;
      const timeStr = `${mins}m ${secs < 10 ? '0' : ''}${secs}s`;

      const todayTimeEl = document.getElementById('metric-today-time');
      if (todayTimeEl) todayTimeEl.textContent = timeStr;

      const pct = Math.min(100, Math.round((this.trackingSeconds / this.dailyLimitSeconds) * 100));
      const budgetFill = document.getElementById('active-budget-fill');
      const budgetText = document.getElementById('active-budget-text');

      if (budgetFill) budgetFill.style.width = `${pct}%`;
      if (budgetText) budgetText.textContent = `${timeStr} / ${Math.floor(this.dailyLimitSeconds / 60)}m 00s (${pct}%)`;

      // State transition check
      const stateBadge = document.getElementById('badge-active-state');
      if (stateBadge) {
        if (pct >= 100) {
          stateBadge.textContent = 'RESTRICTED';
          stateBadge.className = 'badge badge-danger';
        } else if (pct >= 80) {
          stateBadge.textContent = 'WARNING';
          stateBadge.className = 'badge badge-warning';
        } else {
          stateBadge.textContent = 'TRACKING';
          stateBadge.className = 'badge badge-info';
        }
      }
    }, 1000);
  }
}

// Initialize application on DOM ready
window.addEventListener('DOMContentLoaded', () => {
  new FocusGuardApp();
});
