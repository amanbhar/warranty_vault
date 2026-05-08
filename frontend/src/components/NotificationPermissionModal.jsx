import { useState, useEffect } from 'react';

export function NotificationPermissionModal() {
  const [showPrompt, setShowPrompt] = useState(false);
  const [showToast, setShowToast] = useState(null);

  useEffect(() => {
    if (typeof Notification === 'undefined' || Notification.permission !== 'default') {
      return;
    }

    const dismissedTime = localStorage.getItem('notificationPromptDismissed');
    const dismissed = dismissedTime && (Date.now() - parseInt(dismissedTime)) < 24 * 60 * 60 * 1000;

    if (!dismissed) {
      setShowPrompt(true);
    }
  }, []);

  const handleEnableNotifications = () => {
    Notification.requestPermission().then(permission => {
      if (permission === 'granted') {
        setShowToast({ title: 'Success', message: 'Notifications enabled! You\'ll receive important updates.', type: 'success' });
        setTimeout(() => setShowToast(null), 5000);
      }
    });
    setShowPrompt(false);
  };

  const handleDismiss = () => {
    setShowPrompt(false);
    localStorage.setItem('notificationPromptDismissed', Date.now().toString());
  };

  if (!showPrompt) return null;

  return (
    <>
      <div className="fixed inset-0 bg-black/20 z-[10000]" onClick={handleDismiss} />
      <div className="fixed top-4 right-4 sm:top-6 sm:right-6 z-[10001] min-w-[320px] max-w-sm animate-in slide-in-from-right-4 fade-in duration-300">
        <div className="bg-white dark:bg-slate-900 rounded-xl shadow-2xl border border-slate-200 dark:border-slate-800 p-5">
          <div className="flex flex-col gap-4">
            <div className="flex items-center gap-3">
              <div className="flex items-center justify-center w-12 h-12 bg-gradient-to-br from-blue-500 to-blue-700 rounded-xl text-white shrink-0">
                <span className="material-symbols-outlined text-2xl">notifications</span>
              </div>
              <div>
                <h3 className="text-lg font-semibold text-slate-900 dark:text-slate-100">Enable Notifications</h3>
                <p className="text-sm text-slate-600 dark:text-slate-400 mt-0.5">Get instant updates for your products</p>
              </div>
            </div>
            <div className="flex gap-2">
              <button
                onClick={handleEnableNotifications}
                className="flex-1 px-4 py-2.5 bg-gradient-to-r from-blue-500 to-blue-700 text-white rounded-lg font-medium text-sm hover:from-blue-600 hover:to-blue-800 transition-all"
              >
                Enable
              </button>
              <button
                onClick={handleDismiss}
                className="px-4 py-2.5 bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 rounded-lg font-medium text-sm hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors"
              >
                Not now
              </button>
            </div>
          </div>
        </div>
      </div>

      {showToast && (
        <div className="fixed top-4 right-4 sm:top-6 sm:right-6 z-[10002] min-w-[320px] max-w-sm animate-in slide-in-from-right-4 fade-in duration-300">
          <div className="bg-white dark:bg-slate-900 rounded-xl shadow-2xl border border-slate-200 dark:border-slate-800 p-4 border-l-4 border-emerald-500">
            <div className="flex justify-between items-start gap-3">
              <div className="flex-1">
                <p className="font-semibold text-sm text-slate-900 dark:text-slate-100">{showToast.title}</p>
                <p className="text-sm text-slate-600 dark:text-slate-400 mt-1">{showToast.message}</p>
              </div>
              <button
                onClick={() => setShowToast(null)}
                className="text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 transition-colors"
              >
                <span className="material-symbols-outlined text-xl">close</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
