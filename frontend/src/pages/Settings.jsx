import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import useAuthStore from '../store/authStore';
import { userAPI, userReminderPreferencesAPI, invoicesAPI } from '../services/api';
import { Header } from '../components/Header';
import { Layout } from '../components/Layout';
import { Card } from '../components/Card';
import { Button } from '../components/Button';
import { cn } from '../utils/cn';

export function Settings() {
  const navigate = useNavigate();
  const { user, updateUser, logout } = useAuthStore();
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [formData, setFormData] = useState({
    first_name: user?.first_name || '',
    last_name: user?.last_name || '',
  });

  const [preferences, setPreferences] = useState([]);
  const [alertsEnabled, setAlertsEnabled] = useState(true);
  const [exportLoading, setExportLoading] = useState(false);

  useEffect(() => {
    const loadPreferences = async () => {
      try {
        const response = await userReminderPreferencesAPI.get();
        setPreferences(response.data.preferences);
        setAlertsEnabled(response.data.warranty_alerts_enabled);
      } catch (err) {
        console.error('Failed to load preferences', err);
      }
    };
    loadPreferences();
  }, []);

  const handleToggleAlerts = async () => {
    try {
      const response = await userReminderPreferencesAPI.toggleAlerts(!alertsEnabled);
      setAlertsEnabled(response.data.warranty_alerts_enabled);
    } catch (err) {
      console.error('Failed to toggle alerts', err);
    }
  };

  const handleDeletePreference = async (id) => {
    try {
      await userReminderPreferencesAPI.delete(id);
      setPreferences(preferences.filter(p => p.id !== id));
    } catch (err) {
      alert('Failed to delete preference');
    }
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const response = await userAPI.updateProfile(formData);
      updateUser(response.data.user);
      setEditing(false);
    } finally {
      setSaving(false);
    }
  };

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  const showToast = (title, message, type = 'info') => {
    const toast = document.createElement('div');
    toast.className = 'toast-notification';
    toast.style.cssText = `
      position: fixed;
      top: 20px;
      right: 20px;
      background: white;
      border-radius: 12px;
      padding: 16px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.15);
      z-index: 10002;
      min-width: 320px;
      max-width: 400px;
      animation: slideInRight 0.3s ease-out;
      border-left: 4px solid ${type === 'success' ? '#10b981' : type === 'error' ? '#ef4444' : type === 'warning' ? '#f59e0b' : '#3b82f6'};
    `;
    toast.innerHTML = `
      <div style="display: flex; justify-content: space-between; align-items: start; gap: 12px;">
        <div style="flex: 1;">
          <strong style="display: block; margin-bottom: 4px; color: #1f2937; font-size: 14px;">${title}</strong>
          <p style="margin: 0; color: #6b7280; font-size: 13px; line-height: 1.4;">${message}</p>
        </div>
        <button onclick="this.parentElement.parentElement.remove()" style="background: none; border: none; font-size: 18px; cursor: pointer; color: #9ca3af;">&times;</button>
      </div>
      <style>
        @keyframes slideInRight {
          from { transform: translateX(100%); opacity: 0; }
          to { transform: translateX(0); opacity: 1; }
        }
      </style>
    `;
    document.body.appendChild(toast);
    setTimeout(() => {
      if (document.body.contains(toast)) {
        toast.remove();
      }
    }, 5000);
  };

  const handleExportData = async () => {
    if (exportLoading) return;

    setExportLoading(true);
    try {
      const response = await invoicesAPI.export();

      // Get filename from Content-Disposition header
      const contentDisposition = response.headers['content-disposition'];
      let filename = 'invoices.zip';
      if (contentDisposition) {
        const matches = contentDisposition.match(/filename="(.+)"/);
        if (matches) filename = matches[1];
      }

      // Download the ZIP file
      const url = window.URL.createObjectURL(response.data);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);

      // Show success message
      showToast(
        'Export Complete',
        `ZIP file downloaded: ${filename}`,
        'success'
      );
    } catch (error) {
      console.error('Export error:', error);
      showToast(
        'Export Failed',
        error.response?.data?.error || error.message || 'Could not export invoices. Please try again.',
        'error'
      );
    } finally {
      setExportLoading(false);
    }
  };

  return (
    <Layout>
      <Header title="Settings" showBack />

      {/* Profile Section */}
      <section className="p-6">
        <div className="flex items-center gap-5">
          <div className="relative">
            <div className="w-20 h-20 rounded-full bg-primary/10 border-2 border-primary flex items-center justify-center overflow-hidden">
              {user?.avatar_url ? (
                <img
                  src={user.avatar_url}
                  alt={user.full_name}
                  className="w-full h-full object-cover"
                  referrerPolicy="no-referrer"
                  loading="lazy"
                />
              ) : (
                <span className="material-symbols-outlined text-4xl text-primary">person</span>
              )}
            </div>
          </div>
          <div className="flex-1">
            {editing ? (
              <div className="space-y-3">
                <input
                  value={formData.first_name}
                  onChange={(event) => setFormData((current) => ({ ...current, first_name: event.target.value }))}
                  className="input"
                  placeholder="First name"
                />
                <input
                  value={formData.last_name}
                  onChange={(event) => setFormData((current) => ({ ...current, last_name: event.target.value }))}
                  className="input"
                  placeholder="Last name"
                />
              </div>
            ) : (
              <>
                <h2 className="text-xl font-bold text-slate-900 dark:text-slate-100">
                  {user?.full_name || user?.email}
                </h2>
                <p className="text-slate-500 dark:text-slate-400 text-sm">{user?.email}</p>
              </>
            )}
            <span className="inline-flex mt-1 px-2 py-0.5 rounded-full text-xs font-medium bg-primary/10 text-primary border border-primary/20 capitalize">
              {user?.role || 'Member'}
            </span>
          </div>
        </div>

        <div className="mt-4 flex gap-3">
          {editing ? (
            <>
              <Button onClick={handleSave} disabled={saving}>{saving ? 'Saving...' : 'Save profile'}</Button>
              <Button variant="outline" onClick={() => setEditing(false)}>Cancel</Button>
            </>
          ) : (
            <Button variant="outline" onClick={() => setEditing(true)}>Edit profile</Button>
          )}
        </div>
      </section>


      {/* Integrations */}
      {/*<section className="mt-4">
        <h3 className="px-6 py-2 text-sm font-semibold uppercase tracking-wider text-slate-500">Integrations</h3>

        <button
          onClick={() => navigate('/gmail-import')}
          className="w-full flex items-center gap-4 px-6 py-4 bg-white dark:bg-slate-900 hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors"
        >
          <div className="size-10 flex items-center justify-center bg-red-50 dark:bg-red-900/20 rounded-lg">
            <span className="material-symbols-outlined text-red-600">mail</span>
          </div>
          <div className="flex-1 text-left">
            <p className="font-medium text-slate-900 dark:text-slate-100">Gmail Connection</p>
            <p className="text-sm text-slate-500">Import receipts from inbox</p>
          </div>
          <span className="material-symbols-outlined text-slate-400">chevron_right</span>
        </button>
      </section> */}

      {/* Notifications */}
      {/*
        <section className="mt-8 px-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h3 className="text-lg font-bold text-slate-900 dark:text-slate-100">Warranty Alerts</h3>
              <p className="text-sm text-slate-500">Manage how you receive expiration reminders</p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={alertsEnabled}
                onChange={handleToggleAlerts}
                className="sr-only peer"
              />
              <div className="w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer dark:bg-slate-700 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[4px] after:left-[4px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary"></div>
            </label>
          </div>

          <div className={cn("space-y-4 transition-opacity", !alertsEnabled && "opacity-50")}>
            <Card className="p-4 space-y-4">
              <p className="text-xs font-bold text-slate-400 uppercase tracking-widest">Active Reminders</p>

              <div className="space-y-3">
                {preferences.map((pref) => (
                  <div key={pref.id} className="flex items-center justify-between p-4 bg-slate-50 rounded-lg">
                    <div>
                      <p className="font-semibold text-slate-900">{pref.days_before_expiry} days before</p>
                      {pref.description && (
                        <p className="text-xs text-slate-500 mt-1">{pref.description}</p>
                      )}
                    </div>
                    <button onClick={() => handleDeletePreference(pref.id)}>
                      <span className="material-symbols-outlined">delete</span>
                    </button>
                  </div>
                ))}
              </div>
            </Card>
          </div>
        </section>
      */}

      {/* Data & Privacy */}
      <section className="mt-4">
        <h3 className="px-6 py-2 text-sm font-semibold uppercase tracking-wider text-slate-500">Data & Privacy</h3>

        <button 
          onClick={handleExportData}
          disabled={exportLoading}
          className="w-full flex items-center gap-4 px-6 py-4 bg-white dark:bg-slate-900 hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors disabled:opacity-50"
        >
          <div className="size-10 flex items-center justify-center bg-slate-100 dark:bg-slate-800 rounded-lg">
            <span className="material-symbols-outlined text-slate-600 dark:text-slate-300">
              {exportLoading ? 'hourglass_empty' : 'download'}
            </span>
          </div>
          <div className="flex-1 text-left">
            <p className="font-medium text-slate-900 dark:text-slate-100">
              {exportLoading ? 'Preparing Download...' : 'Export Data'}
            </p>
            <p className="text-sm text-slate-500">
              {exportLoading ? 'Creating ZIP file...' : 'Download all receipts as ZIP'}
            </p>
          </div>
          <span className="material-symbols-outlined text-slate-400">
            {exportLoading ? 'schedule' : 'chevron_right'}
          </span>
        </button>

        <button
          onClick={() => {
            if (confirm('Are you sure? This will permanently delete your account.')) {
              handleLogout();
            }
          }}
          className="w-full flex items-center gap-4 px-6 py-4 bg-white dark:bg-slate-900 hover:bg-red-50 dark:hover:bg-red-900/10 transition-colors"
        >
          <div className="size-10 flex items-center justify-center bg-red-50 dark:bg-red-900/20 rounded-lg">
            <span className="material-symbols-outlined text-red-600">delete_forever</span>
          </div>
          <div className="flex-1 text-left">
            <p className="font-medium text-red-600">Delete Account</p>
            <p className="text-sm text-slate-500">Permanently erase all your data</p>
          </div>
          <span className="material-symbols-outlined text-slate-400">chevron_right</span>
        </button>
      </section>

      {/* Logout */}
      <section className="px-6 pb-6">
        <Button onClick={handleLogout} variant="outline" className="w-full">
          Log Out
        </Button>
      </section>
    </Layout>
  );
}
