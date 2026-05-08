import React, { useState, useEffect, useRef } from 'react';
import { useWebSocket } from '../hooks/useWebSocket';
import useNotificationStore from '../store/notificationStore';
import './NotificationBell.css';

const NotificationBell = ({ token, onNotificationClick }) => {
  const [showDropdown, setShowDropdown] = useState(false);
  const dropdownRef = useRef(null);

  // Use notification store
  const {
    notifications,
    unreadCount,
    loading,
    pagination,
    fetchNotifications
  } = useNotificationStore();

  const {
    isConnected,
    lastNotification,
    markNotificationAsRead,
    markAllNotificationsAsRead,
    setNotificationHandler,
    setUnreadCountHandler
  } = useWebSocket(token);

  // Fetch notifications on mount and when page changes
  useEffect(() => {
    if (token) {
      fetchNotifications({ per_page: 10, page: pagination.currentPage });
    }
  }, [token, pagination.currentPage, fetchNotifications]);

  // Request browser notification permission with user-friendly prompt
  useEffect(() => {
    if (token && "Notification" in window) {
      if (Notification.permission === "default") {
        // Show a custom prompt before requesting browser permission
        const showCustomPrompt = () => {
          const promptDiv = document.createElement('div');
          promptDiv.className = 'notification-permission-prompt';
          promptDiv.innerHTML = `
            <div class="prompt-content">
              <div class="prompt-icon">
                <span class="material-symbols-outlined">notifications</span>
              </div>
              <div class="prompt-text">
                <h3>Enable Notifications</h3>
                <p>Stay updated with your warranty reminders and important product updates. Enable notifications to never miss an expiry alert.</p>
              </div>
              <div class="prompt-actions">
                <button class="btn-enable" onclick="enableNotifications()">Enable</button>
                <button class="btn-dismiss" onclick="dismissPrompt()">Not now</button>
              </div>
            </div>
          `;

          // Add styles
          promptDiv.innerHTML += `
            <style>
              .notification-permission-prompt {
                position: fixed;
                top: 20px;
                right: 20px;
                background: white;
                border-radius: 12px;
                padding: 20px;
                box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
                z-index: 10001;
                min-width: 320px;
                max-width: 400px;
                animation: slideInRight 0.3s ease-out;
                border: 1px solid #e5e7eb;
              }
              
              .prompt-content {
                display: flex;
                flex-direction: column;
                gap: 16px;
              }
              
              .prompt-icon {
                display: flex;
                align-items: center;
                justify-content: center;
                width: 48px;
                height: 48px;
                background: linear-gradient(135deg, #3b82f6, #1d4ed8);
                border-radius: 12px;
                color: white;
                margin-bottom: 8px;
              }
              
              .prompt-icon span {
                font-size: 24px;
              }
              
              .prompt-text h3 {
                margin: 0 0 8px 0;
                color: #1f2937;
                font-size: 18px;
                font-weight: 600;
              }
              
              .prompt-text p {
                margin: 0;
                color: #6b7280;
                font-size: 14px;
                line-height: 1.5;
              }
              
              .prompt-actions {
                display: flex;
                gap: 12px;
                margin-top: 8px;
              }
              
              .btn-enable, .btn-dismiss {
                padding: 10px 20px;
                border-radius: 8px;
                border: none;
                font-size: 14px;
                font-weight: 500;
                cursor: pointer;
                transition: all 0.2s ease;
              }
              
              .btn-enable {
                background: linear-gradient(135deg, #3b82f6, #1d4ed8);
                color: white;
                flex: 1;
              }
              
              .btn-enable:hover {
                background: linear-gradient(135deg, #2563eb, #1e40af);
                transform: translateY(-1px);
                box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
              }
              
              .btn-dismiss {
                background: #f3f4f6;
                color: #6b7280;
              }
              
              .btn-dismiss:hover {
                background: #e5e7eb;
                color: #4b5563;
              }
              
              @keyframes slideInRight {
                from {
                  transform: translateX(100%);
                  opacity: 0;
                }
                to {
                  transform: translateX(0);
                  opacity: 1;
                }
              }
            </style>
          `;

          // Add global functions
          window.enableNotifications = () => {
            Notification.requestPermission().then(permission => {
              console.log("Browser notification permission:", permission);
              if (permission === "granted") {
                // Show success message
                showSuccessMessage("Notifications enabled! You'll receive important updates.");
              } else if (permission === "denied") {
                showInfoMessage("Notifications disabled. You can enable them in your browser settings.");
              }
            });
            document.body.removeChild(promptDiv);
          };

          window.dismissPrompt = () => {
            document.body.removeChild(promptDiv);
            // Store preference to not show again for 24 hours
            localStorage.setItem('notificationPromptDismissed', Date.now().toString());
          };

          // Add to DOM
          document.body.appendChild(promptDiv);

          // Auto-dismiss after 10 seconds
          setTimeout(() => {
            if (document.body.contains(promptDiv)) {
              document.body.removeChild(promptDiv);
            }
          }, 10000);
        };

        // Check if user recently dismissed the prompt
        const dismissedTime = localStorage.getItem('notificationPromptDismissed');
        if (dismissedTime) {
          const timeDiff = Date.now() - parseInt(dismissedTime);
          const hoursDiff = timeDiff / (1000 * 60 * 60);

          // Only show prompt if it's been more than 24 hours since dismissal
          if (hoursDiff > 24) {
            localStorage.removeItem('notificationPromptDismissed');
            showCustomPrompt();
          }
        } else {
          showCustomPrompt();
        }
      } else if (Notification.permission === "granted") {
        console.log("Browser notifications already granted");
      } else if (Notification.permission === "denied") {
        console.log("Browser notifications denied by user");
      }
    }
  }, [token]);

  // Handle new notification
  useEffect(() => {
    if (lastNotification) {
      // Let the store handle new notifications through WebSocket
      // The store will update automatically
      console.log('New notification received:', lastNotification);

      // Show in-app toast notification
      showToast(lastNotification);

      // Show OS-level browser notification if permitted
      if ("Notification" in window && Notification.permission === "granted") {
        const osNotification = new Notification(lastNotification.title, {
          body: lastNotification.message,
          icon: '/favicon.ico' // fallback icon
        });

        osNotification.onclick = () => {
          window.focus();
          osNotification.close();
        };
      }
    }
  }, [lastNotification]);

  // Handle unread count updates
  useEffect(() => {
    setUnreadCountHandler((count) => {
      // Could update local state or show badge animation
      console.log('Unread count updated:', count);
    });
  }, [setUnreadCountHandler]);

  // Show toast notification
  const showToast = (notification) => {
    // Create toast element
    const toast = document.createElement('div');
    toast.className = `notification-toast ${notification.notification_type}`;
    toast.innerHTML = `
      <div class="toast-content">
        <strong>${notification.title}</strong>
        <p>${notification.message}</p>
      </div>
      <button class="toast-close">&times;</button>
    `;

    // Add to DOM
    document.body.appendChild(toast);

    // Auto remove after 5 seconds
    setTimeout(() => {
      if (toast.parentNode) {
        toast.parentNode.removeChild(toast);
      }
    }, 5000);

    // Close button handler
    toast.querySelector('.toast-close').addEventListener('click', () => {
      if (toast.parentNode) {
        toast.parentNode.removeChild(toast);
      }
    });
  };

  // Show success message
  const showSuccessMessage = (message) => {
    const successDiv = document.createElement('div');
    successDiv.className = 'notification-toast success';
    successDiv.innerHTML = `
      <div class="toast-content">
        <strong>Success!</strong>
        <p>${message}</p>
      </div>
      <button class="toast-close">&times;</button>
    `;

    document.body.appendChild(successDiv);

    setTimeout(() => {
      if (successDiv.parentNode) {
        successDiv.parentNode.removeChild(successDiv);
      }
    }, 4000);

    successDiv.querySelector('.toast-close').addEventListener('click', () => {
      if (successDiv.parentNode) {
        successDiv.parentNode.removeChild(successDiv);
      }
    });
  };

  // Show info message
  const showInfoMessage = (message) => {
    const infoDiv = document.createElement('div');
    infoDiv.className = 'notification-toast info';
    infoDiv.innerHTML = `
      <div class="toast-content">
        <strong>Info</strong>
        <p>${message}</p>
      </div>
      <button class="toast-close">&times;</button>
    `;

    document.body.appendChild(infoDiv);

    setTimeout(() => {
      if (infoDiv.parentNode) {
        infoDiv.parentNode.removeChild(infoDiv);
      }
    }, 4000);

    infoDiv.querySelector('.toast-close').addEventListener('click', () => {
      if (infoDiv.parentNode) {
        infoDiv.parentNode.removeChild(infoDiv);
      }
    });
  };

  // Handle notification click
  const handleNotificationClick = (notification) => {
    if (notification.action_url) {
      onNotificationClick?.(notification);
    }

    // Mark as read using store
    const { markAsRead } = useNotificationStore.getState();
    markAsRead(notification.id);

    setShowDropdown(false);
  };

  // Handle mark all as read
  const handleMarkAllRead = () => {
    markAllNotificationsAsRead();

    // Also update store
    const { markAllAsRead } = useNotificationStore.getState();
    markAllAsRead();
  };

  // Handle pagination
  const handlePageChange = (newPage) => {
    const { fetchNotifications } = useNotificationStore.getState();
    fetchNotifications({ per_page: 10, page: newPage });
  };

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target)) {
        setShowDropdown(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, []);

  return (
    <div className="notification-bell-container">
      {/* Bell Icon with Badge */}
      <button
        className={`notification-bell ${isConnected ? 'connected' : 'disconnected'}`}
        onClick={() => setShowDropdown(!showDropdown)}
        title={isConnected ? 'Notifications' : 'Connecting...'}
      >
        <span className="material-symbols-outlined">
          notifications
        </span>

        {unreadCount > 0 && (
          <span className="notification-badge">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}

        <div className={`connection-indicator ${isConnected ? 'online' : 'offline'}`} />
      </button>

      {/* Dropdown */}
      {showDropdown && (
        <div className="notification-dropdown" ref={dropdownRef}>
          <div className="notification-header">
            <h3>Notifications</h3>
            {unreadCount > 0 && (
              <button
                className="mark-all-read"
                onClick={handleMarkAllRead}
              >
                Mark all as read
              </button>
            )}
          </div>

          <div className="notification-list">
            {loading ? (
              <div className="loading-notifications">
                <div className="loading-spinner"></div>
                <p>Loading notifications...</p>
              </div>
            ) : notifications.length === 0 ? (
              <div className="no-notifications">
                <span className="material-symbols-outlined">
                  notifications_none
                </span>
                <p>You're all up to date</p>
              </div>
            ) : (
              <>
                {notifications.map(notification => (
                  <div
                    key={notification.id}
                    className={`notification-item ${notification.read ? 'read' : 'unread'}`}
                    onClick={() => handleNotificationClick(notification)}
                  >
                    <div className="notification-content">
                      <div className="notification-title">
                        {notification.title}
                      </div>
                      <div className="notification-message">
                        {notification.message}
                      </div>
                      <div className="notification-time">
                        {new Date(notification.created_at).toLocaleString()}
                      </div>
                    </div>

                    {!notification.read && (
                      <div className="unread-indicator" />
                    )}
                  </div>
                ))}

                {/* Pagination Controls */}
                {pagination.totalPages > 1 && (
                  <div className="pagination-controls">
                    <button
                      className="pagination-btn"
                      onClick={() => handlePageChange(pagination.currentPage - 1)}
                      disabled={pagination.currentPage === 1}
                    >
                      <span className="material-symbols-outlined">chevron_left</span>
                    </button>

                    <span className="pagination-info">
                      {pagination.currentPage} of {pagination.totalPages}
                    </span>

                    <button
                      className="pagination-btn"
                      onClick={() => handlePageChange(pagination.currentPage + 1)}
                      disabled={pagination.currentPage === pagination.totalPages}
                    >
                      <span className="material-symbols-outlined">chevron_right</span>
                    </button>
                  </div>
                )}
              </>
            )}
          </div>

          {notifications.length > 0 && (
            <div className="notification-footer">
              <button className="view-all-notifications">
                View all notifications
              </button>
            </div>
          )}
        </div>
      )}

      {/* Toast Container Styles */}
      <style jsx>{`
        .notification-toast {
          position: fixed;
          top: 20px;
          right: 20px;
          background: white;
          border-radius: 8px;
          padding: 16px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
          z-index: 10000;
          min-width: 300px;
          max-width: 400px;
          animation: slideIn 0.3s ease-out;
        }

        .notification-toast.info {
          border-left: 4px solid #3b82f6;
        }

        .notification-toast.warning {
          border-left: 4px solid #f59e0b;
        }

        .notification-toast.error {
          border-left: 4px solid #ef4444;
        }

        .notification-toast.success {
          border-left: 4px solid #10b981;
        }

        .toast-content strong {
          display: block;
          margin-bottom: 4px;
          color: #1f2937;
        }

        .toast-content p {
          margin: 0;
          color: #6b7280;
          font-size: 14px;
        }

        .toast-close {
          position: absolute;
          top: 8px;
          right: 8px;
          background: none;
          border: none;
          font-size: 18px;
          cursor: pointer;
          color: #9ca3af;
        }

        @keyframes slideIn {
          from {
            transform: translateX(100%);
            opacity: 0;
          }
          to {
            transform: translateX(0);
            opacity: 1;
          }
        }
      `}</style>
    </div>
  );
};

export default NotificationBell;
