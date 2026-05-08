import { useState, useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Layout } from '../components/Layout';
import { Header } from '../components/Header';
import useNotificationStore from '../store/notificationStore';

export function Notifications() {
  const navigate = useNavigate();
  const { fetchNotifications, markAsRead } = useNotificationStore();
  const [notifications, setNotifications] = useState([]);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [initialLoad, setInitialLoad] = useState(true);
  const sentinelRef = useRef(null);
  const PER_PAGE = 20;

  const loadPage = useCallback(async (pageNum) => {
    if (loading) return;
    setLoading(true);
    try {
      const result = await fetchNotifications({ page: pageNum, per_page: PER_PAGE });
      // fetchNotifications returns { notifications, pagination }
      // Append to existing list for infinite scroll
      if (pageNum === 1) {
        setNotifications(result.notifications || []);
      } else {
        setNotifications(prev => [...prev, ...(result.notifications || [])]);
      }
      const pagination = result.pagination;
      setHasMore(pagination ? pageNum < pagination.total_pages : false);
    } finally {
      setLoading(false);
      setInitialLoad(false);
    }
  }, [fetchNotifications]);

  // Initial load
  useEffect(() => {
    loadPage(1);
  }, []);

  // IntersectionObserver for infinite scroll
  useEffect(() => {
    if (!sentinelRef.current || !hasMore || loading) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !loading) {
          setPage(prev => {
            const next = prev + 1;
            loadPage(next);
            return next;
          });
        }
      },
      { threshold: 0.1 }
    );
    observer.observe(sentinelRef.current);
    return () => observer.disconnect();
  }, [hasMore, loading, loadPage]);

  const iconMap = {
    warranty_expiring: { icon: 'notifications_active', color: 'text-orange-500 bg-orange-50' },
    warranty_expired: { icon: 'notifications_active', color: 'text-red-500 bg-red-50' },
    invoice_created: { icon: 'receipt_long', color: 'text-blue-500 bg-blue-50' },
    invoice_updated: { icon: 'receipt_long', color: 'text-blue-500 bg-blue-50' },
    product_updated: { icon: 'inventory_2', color: 'text-blue-500 bg-blue-50' },
    success: { icon: 'check_circle', color: 'text-green-500 bg-green-50' },
    error: { icon: 'error', color: 'text-red-500 bg-red-50' },
  };

  const handleClick = (notification) => {
    markAsRead(notification.id);
    const url = notification.action_url || '/dashboard';
    navigate(url);
  };

  return (
    <Layout>
      <Header title="Notifications" showBack={true} />
      <div className="max-w-2xl mx-auto py-6 px-4">
        {initialLoad ? (
          // skeleton loader — show 5 placeholder items
          Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="flex gap-3 p-4 mb-2 bg-white rounded-xl animate-pulse">
              <div className="w-10 h-10 bg-slate-200 rounded-full flex-shrink-0" />
              <div className="flex-1 space-y-2">
                <div className="h-3 bg-slate-200 rounded w-1/3" />
                <div className="h-3 bg-slate-200 rounded w-2/3" />
                <div className="h-2 bg-slate-100 rounded w-1/4" />
              </div>
            </div>
          ))
        ) : notifications.length === 0 ? (
          <div className="text-center py-20">
            <span className="material-symbols-outlined text-5xl text-slate-300">notifications_none</span>
            <p className="text-slate-500 mt-3 text-sm">No notifications yet</p>
          </div>
        ) : (
          <>
            {notifications.map(notification => {
              const iconInfo = iconMap[notification.notification_type] || 
                               { icon: 'notifications', color: 'text-slate-400 bg-slate-50' };
              return (
                <button
                  key={notification.id}
                  onClick={() => handleClick(notification)}
                  className={`w-full flex items-start gap-3 p-4 mb-2 rounded-xl text-left 
                              border transition-colors
                              ${!notification.read 
                                ? 'bg-blue-50/50 border-blue-100 dark:bg-blue-900/10 dark:border-blue-900/30' 
                                : 'bg-white border-slate-100 dark:bg-slate-900 dark:border-slate-800'}
                              hover:bg-slate-50 dark:hover:bg-slate-800`}
                >
                  <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 ${iconInfo.color}`}>
                    <span className="material-symbols-outlined text-lg">{iconInfo.icon}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between gap-2">
                      <p className={`text-sm font-semibold ${!notification.read ? 'text-slate-900' : 'text-slate-700'} dark:text-slate-100`}>
                        {notification.title}
                      </p>
                      {!notification.read && (
                        <span className="w-2 h-2 bg-blue-500 rounded-full flex-shrink-0" />
                      )}
                    </div>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5 line-clamp-2">
                      {notification.message}
                    </p>
                    <p className="text-[10px] text-slate-400 mt-1.5">
                      {new Date(notification.created_at).toLocaleString()}
                    </p>
                  </div>
                </button>
              );
            })}

            {/* Sentinel for IntersectionObserver */}
            <div ref={sentinelRef} className="h-8 flex items-center justify-center">
              {loading && (
                <div className="w-5 h-5 border-2 border-primary border-t-transparent rounded-full animate-spin" />
              )}
            </div>

            {!hasMore && notifications.length > 0 && (
              <p className="text-center text-xs text-slate-400 py-4">
                You're all caught up ✓
              </p>
            )}
          </>
        )}
      </div>
    </Layout>
  );
}
