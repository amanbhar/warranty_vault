import { useState, useEffect, useCallback, useRef } from 'react';
import websocketService from '../services/websocketService';

// Custom hook for WebSocket functionality
export const useWebSocket = (token) => {
  const [isConnected, setIsConnected] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  const [lastNotification, setLastNotification] = useState(null);
  const [lastWarrantyUpdate, setLastWarrantyUpdate] = useState(null);
  const [lastProductUpdate, setLastProductUpdate] = useState(null);
  const [connectionError, setConnectionError] = useState(null);
  
  const callbacksRef = useRef({
    onNewNotification: null,
    onUnreadCountUpdate: null,
    onWarrantyUpdate: null,
    onProductUpdate: null,
    onConnectionChange: null
  });

  // Connect to WebSocket
  const connect = useCallback((authToken) => {
    if (!authToken) {
      console.error('[useWebSocket] No token provided');
      return;
    }
    
    websocketService.token = authToken;
    websocketService.connect(authToken);
  }, []);

  // Disconnect from WebSocket
  const disconnect = useCallback(() => {
    websocketService.disconnect();
  }, []);

  // Mark notification as read
  const markNotificationAsRead = useCallback((notificationId) => {
    websocketService.markNotificationAsRead(notificationId);
  }, []);

  // Mark all notifications as read
  const markAllNotificationsAsRead = useCallback(() => {
    websocketService.markAllNotificationsAsRead();
  }, []);

  // Update warranty status
  const updateWarrantyStatus = useCallback((warrantyId, status) => {
    websocketService.updateWarrantyStatus(warrantyId, status);
  }, []);

  // Set up event handlers
  useEffect(() => {
    // Connection handlers
    websocketService.onConnectionChange = (connected) => {
      setIsConnected(connected);
      setConnectionError(null);
      callbacksRef.current.onConnectionChange?.(connected);
    };

    // Notification handlers
    websocketService.onNewNotification = (notification) => {
      setLastNotification(notification);
      callbacksRef.current.onNewNotification?.(notification);
    };

    websocketService.onUnreadCountUpdate = (count) => {
      setUnreadCount(count);
      callbacksRef.current.onUnreadCountUpdate?.(count);
    };

    // Warranty handlers
    websocketService.onWarrantyStatusUpdate = (data) => {
      setLastWarrantyUpdate(data);
      callbacksRef.current.onWarrantyUpdate?.(data);
    };

    websocketService.onWarrantyExpiryAlert = (data) => {
      callbacksRef.current.onWarrantyUpdate?.(data);
    };

    websocketService.onWarrantyCreated = (data) => {
      callbacksRef.current.onWarrantyUpdate?.(data);
    };

    websocketService.onProductUpdated = (data) => {
      setLastProductUpdate(data);
      callbacksRef.current.onProductUpdate?.(data);
    };

    // Error handler
    websocketService.onError = (error) => {
      setConnectionError(error);
      console.error('[useWebSocket] WebSocket error:', error);
    };

    return () => {
      // Cleanup
      websocketService.onConnectionChange = null;
      websocketService.onNewNotification = null;
      websocketService.onUnreadCountUpdate = null;
      websocketService.onWarrantyStatusUpdate = null;
      websocketService.onWarrantyExpiryAlert = null;
      websocketService.onWarrantyCreated = null;
      websocketService.onProductUpdated = null;
      websocketService.onError = null;
    };
  }, []);

  // Auto-connect when token changes
  useEffect(() => {
    if (token) {
      connect(token);
    }

    return () => {
      disconnect();
    };
  }, [token, connect, disconnect]);

  return {
    // Connection state
    isConnected,
    connectionError,
    
    // Notification state
    unreadCount,
    lastNotification,
    
    // Warranty state
    lastWarrantyUpdate,
    lastProductUpdate,
    
    // Actions
    connect,
    disconnect,
    markNotificationAsRead,
    markAllNotificationsAsRead,
    updateWarrantyStatus,
    
    // Event handlers (for custom handling)
    setNotificationHandler: (handler) => {
      callbacksRef.current.onNewNotification = handler;
    },
    setUnreadCountHandler: (handler) => {
      callbacksRef.current.onUnreadCountUpdate = handler;
    },
    setWarrantyHandler: (handler) => {
      callbacksRef.current.onWarrantyUpdate = handler;
    },
    setProductHandler: (handler) => {
      callbacksRef.current.onProductUpdate = handler;
    },
    setConnectionHandler: (handler) => {
      callbacksRef.current.onConnectionChange = handler;
    }
  };
};

export default useWebSocket;
