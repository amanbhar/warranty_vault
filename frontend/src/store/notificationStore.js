import { create } from 'zustand';
import { notificationsAPI, isAuthenticated } from '../services/api';

const useNotificationStore = create((set, get) => ({
  notifications: [],
  unreadCount: 0,
  loading: false,
  pagination: {
    currentPage: 1,
    totalPages: 1,
    totalCount: 0,
  },

  // Fetch notifications
  fetchNotifications: async (params = {}) => {
    set({ loading: true });
    try {
      const response = await notificationsAPI.getAll(params);
      const { notifications, pagination, unread_count } = response.data;

      set({
        notifications,
        unreadCount: unread_count,
        pagination,
        loading: false
      });

      return { notifications, pagination, unread_count };
    } catch (error) {
      if (isAuthenticated()) console.error('Failed to fetch notifications:', error);
      set({ loading: false });
      return { notifications: [], pagination: null, unread_count: 0 };
    }
  },

  // Mark as read
  markAsRead: async (id) => {
    try {
      await notificationsAPI.markAsRead(id);

      set((state) => ({
        notifications: state.notifications.map((n) =>
          n.id === id ? { ...n, read: true } : n
        ),
        unreadCount: Math.max(0, state.unreadCount - 1),
      }));
    } catch (error) {
      if (isAuthenticated()) console.error('Failed to mark notification as read:', error);
    }
  },

  // Mark all as read
  markAllAsRead: async () => {
    try {
      await notificationsAPI.markAllAsRead();

      set((state) => ({
        notifications: state.notifications.map((n) => ({ ...n, read: true })),
        unreadCount: 0,
      }));
    } catch (error) {
      // Handle 404 or other errors gracefully
      console.log('Mark all as read API not available');

      // Fallback: update local state only
      set((state) => ({
        notifications: state.notifications.map((n) => ({ ...n, read: true })),
        unreadCount: 0,
      }));
    }
  },

  // Delete notification
  deleteNotification: async (id) => {
    try {
      await notificationsAPI.delete(id);

      set((state) => ({
        notifications: state.notifications.filter((n) => n.id !== id),
        unreadCount: state.unreadCount,
      }));
    } catch (error) {
      if (isAuthenticated()) console.error('Failed to delete notification:', error);
    }
  },

  // Clear all
  clearAll: async () => {
    try {
      await notificationsAPI.clearAll();
      set({ notifications: [], unreadCount: 0 });
    } catch (error) {
      if (isAuthenticated()) console.error('Failed to clear notifications:', error);
    }
  },

  // Add new notification (for real-time updates)
  addNotification: (notification) => {
    set((state) => ({
      notifications: [notification, ...state.notifications].slice(0, 50), // Keep only last 50
      unreadCount: state.unreadCount + 1,
    }));
  },
}));

export default useNotificationStore;
