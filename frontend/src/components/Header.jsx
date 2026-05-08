import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import useAuthStore from '../store/authStore';
import useNotificationStore from '../store/notificationStore';
import cable from '../cable';
import { cn } from '../utils/cn';
import { NotificationPermissionModal } from './NotificationPermissionModal';

export function Header({ title, showBack = false, standalone = false }) {
  const navigate = useNavigate();
  const { user } = useAuthStore();
  const { notifications, unreadCount, fetchNotifications, markAsRead } = useNotificationStore();
  const [showNotifications, setShowNotifications] = useState(false);
  const [showToast, setShowToast] = useState(null);
  const notificationDropdownRef = useRef(null);

  // Fetch notifications on mount
  useEffect(() => {
    if (user) {
      fetchNotifications({ per_page: 10 });
    }
  }, [user]);

  // Subscribe to notifications via WebSocket
  useEffect(() => {
    if (!user) return;

    const subscription = cable.subscriptions.create(
      { channel: 'NotificationChannel' },
      {
        connected: () => {
          console.log('[Header] Connected to NotificationChannel');
        },
        disconnected: () => {
          console.log('[Header] Disconnected from NotificationChannel');
        },
        rejected: () => {
          console.error('[Header] WebSocket subscription rejected');
        },
        received: (data) => {
          console.log('[Header] Received notification:', data);
          if (data.type === 'new_notification') {
            // Show toast
            setShowToast({
              title: data.title,
              message: data.message,
              type: data.notification_type
            });

            // Auto-hide after 5 seconds
            setTimeout(() => {
              setShowToast(null);
            }, 5000);

            // Refresh notifications list
            fetchNotifications({ per_page: 10 });
          } else if (data.type === 'unread_count_update') {
            // Update unread count
            useNotificationStore.getState().setUnreadCount(data.unread_count);
          }
        }
      }
    );

    return () => {
      subscription.unsubscribe();
    };
  }, [user]);

  // Close notification dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event) => {
      if (notificationDropdownRef.current && !notificationDropdownRef.current.contains(event.target)) {
        setShowNotifications(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, []);

  // Handle notification click
  const handleNotificationClick = (notification) => {
    markAsRead(notification.id);
    setShowNotifications(false);
    
    // Determine the correct URL based on notification type and metadata
    let targetUrl = notification.action_url;
    
    // Fallback logic for different notification types
    if (!targetUrl && notification.metadata) {
      switch (notification.notification_type) {
        case 'invoice_processed':
        case 'warranty_expiring':
        case 'warranty_expired':
        case 'success':
        case 'ocr_complete':
          if (notification.metadata.invoice_id) {
            targetUrl = `/invoice/${notification.metadata.invoice_id}`;
          } else if (notification.metadata.product_id) {
            targetUrl = `/invoice/${notification.metadata.product_id}`;
          }
          break;
        case 'error':
          if (notification.metadata.invoice_id) {
            targetUrl = `/invoice/${notification.metadata.invoice_id}/edit`;
          }
          break;
        case 'system_update':
        case 'info':
        default:
          targetUrl = '/dashboard';
          break;
      }
    }
    
    // Final fallback to dashboard if no URL determined
    if (!targetUrl) {
      targetUrl = '/dashboard';
    }
    
    console.log('Navigating to:', targetUrl, 'from notification:', notification);
    navigate(targetUrl);
  };

  // Handle mark all as read
  const handleMarkAllAsRead = async () => {
    try {
      // Try the API endpoint
      const response = await fetch('/api/v1/notifications/mark_all_as_read', {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('authToken')}`,
          'Content-Type': 'application/json',
        },
      });
      
      // Handle 404 (endpoint doesn't exist) gracefully
      if (response.status === 404) {
        console.log('Mark all as read endpoint not available, using local fallback');
      } else if (response.ok) {
        // Refresh notifications
        fetchNotifications({ per_page: 10 });
        return;
      }
    } catch (error) {
      console.log('Mark all as read API not available, using local fallback');
    }
    
    // Fallback: mark all local notifications as read
    const { notifications } = useNotificationStore.getState();
    notifications.forEach(n => {
      if (!n.read) {
        markAsRead(n.id);
      }
    });
    
    // Refresh to show updated state
    fetchNotifications({ per_page: 10 });
  };

  // Show browser notification
  const showBrowserNotification = (notification) => {
    if ("Notification" in window && Notification.permission === "granted") {
      new Notification(notification.title, {
        body: notification.message,
        icon: '/favicon.ico',
        tag: notification.id,
      });
    }
  };

  return (
    <>
      <NotificationPermissionModal />

      {/* Toast for WebSocket notifications */}
      {showToast && (
        <div className="fixed top-4 right-4 sm:top-6 sm:right-6 z-[10002] min-w-[320px] max-w-sm animate-in slide-in-from-right-4 fade-in duration-300">
          <div className="bg-white dark:bg-slate-900 rounded-xl shadow-2xl border border-slate-200 dark:border-slate-800 p-4 border-l-4 border-blue-500">
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

      <div className={standalone ? "lg:pl-64" : ""}>
      <header className="sticky top-0 z-40 bg-white dark:bg-slate-900 border-b border-slate-200 dark:border-slate-800">
        <div className="px-4 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3">
            {showBack && (
              <button
                onClick={() => navigate(-1)}
                className="p-2 hover:bg-slate-200 dark:hover:bg-slate-800 rounded-full transition-colors"
              >
                <span className="material-symbols-outlined">arrow_back</span>
              </button>
            )}

            {title ? (
              <h1 className="text-lg font-bold text-slate-900 dark:text-slate-100">{title}</h1>
            ) : (
              <div className="flex items-center gap-2">
                <div className="size-10 rounded-full bg-primary/10 flex items-center justify-center">
                  <span className="material-symbols-outlined text-primary">verified_user</span>
                </div>
                <span className="font-bold text-slate-900 dark:text-slate-100">Warranty Vault</span>
              </div>
            )}
          </div>

          <div className="flex items-center gap-2">
            <div className="relative" ref={notificationDropdownRef}>
              <button
                onClick={() => {
                  fetchNotifications({ per_page: 10 });
                  setShowNotifications(!showNotifications);
                }}
                className="relative p-2 hover:bg-primary/10 rounded-lg transition-colors"
                title="Notifications"
              >
                <span className="material-symbols-outlined text-slate-600 dark:text-slate-300">notifications</span>
                {unreadCount > 0 && (
                  <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] bg-red-500 rounded-full text-white text-[10px] font-bold flex items-center justify-center px-1 leading-none">
                    {unreadCount > 99 ? '99+' : unreadCount}
                  </span>
                )}
              </button>

              {/* Notification Dropdown — rendered INSIDE this relative wrapper */}
              {showNotifications && (
                <div className="absolute top-12 right-0 w-80 max-w-[calc(100vw-1rem)] max-h-[520px] bg-white dark:bg-slate-900 rounded-xl shadow-2xl border border-slate-200 dark:border-slate-800 z-50 overflow-hidden animate-in fade-in slide-in-from-top-2">
                  <div className="p-4 border-b border-slate-200 dark:border-slate-800 flex items-center justify-between">
                    <h3 className="font-bold text-slate-900 dark:text-slate-100">Notifications</h3>
                    {unreadCount > 0 && (
                      <button
                        onClick={handleMarkAllAsRead}
                        className="text-xs text-primary font-semibold hover:underline"
                      >
                        Mark all as read
                      </button>
                    )}
                  </div>

                  <div className="overflow-y-auto max-h-[420px]">
                    {notifications.length === 0 ? (
                      <div className="p-8 text-center">
                        <span className="material-symbols-outlined text-4xl text-slate-300 dark:text-slate-600">notifications_none</span>
                        <p className="text-sm text-slate-500 mt-2">No notifications yet</p>
                      </div>
                    ) : (
                      notifications.map(notification => (
                        <button
                          key={notification.id}
                          onClick={() => handleNotificationClick(notification)}
                          className={`w-full p-4 text-left border-b border-slate-100 dark:border-slate-800 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors ${!notification.read ? 'bg-primary/5' : ''}`}
                        >
                          <div className="flex items-start gap-3">
                            <div className={`w-2 h-2 rounded-full mt-2 ${!notification.read ? 'bg-primary' : 'bg-transparent'}`}></div>
                            <div className="flex-1">
                              <p className="font-semibold text-sm text-slate-900 dark:text-slate-100">{notification.title}</p>
                              <p className="text-xs text-slate-600 dark:text-slate-400 mt-1">{notification.message}</p>
                              <p className="text-[10px] text-slate-400 mt-2">
                                {new Date(notification.created_at).toLocaleString()}
                              </p>
                            </div>
                          </div>
                        </button>
                      ))
                    )}
                  </div>

                  {notifications.length > 0 && (
                    <div className="p-3 border-t border-slate-200 dark:border-slate-800">
                      <button
                        onClick={() => {
                          setShowNotifications(false);
                          navigate('/notifications');
                        }}
                        className="w-full py-2 text-sm font-semibold text-primary hover:bg-primary/10 rounded-lg transition-colors"
                      >
                        View All Notifications
                      </button>
                    </div>
                  )}
                </div>
              )}
            </div>

            <button
              onClick={() => navigate('/settings')}
              className="p-2 hover:bg-primary/10 rounded-lg transition-colors"
            >
              <span className="material-symbols-outlined text-slate-600 dark:text-slate-300">settings</span>
            </button>
          </div>
        </div>
      </header>
      </div>
    </>
  );
}
