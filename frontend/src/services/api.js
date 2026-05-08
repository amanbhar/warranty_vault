import axios from 'axios';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3005';

export const isAuthenticated = () => !!localStorage.getItem('authToken');

const PUBLIC_ENDPOINT_PATTERNS = [
  '/api/v1/auth/login',
  '/api/v1/auth/signup',
  '/api/v1/auth/forgot_password',
  '/api/v1/auth/reset_password',
  '/api/v1/verify_email',
  '/api/v1/resend_verification',
];

const isPublicEndpoint = (url = '') => PUBLIC_ENDPOINT_PATTERNS.some((pattern) => url.includes(pattern));

// Create axios instance
const api = axios.create({
  baseURL: API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
  withCredentials: false,
  xsrfCookieName: false,
  xsrfHeaderName: false
});

// Request interceptor
api.interceptors.request.use(
  (config) => {
    const isAuthRequest = isPublicEndpoint(config.url);

    // 2️⃣ API CALL GUARD
    if (!isAuthenticated() && !isAuthRequest) {
      const controller = new AbortController();
      config.signal = controller.signal;
      controller.abort("Unauthenticated");
    }

    if (import.meta.env.DEV && isAuthenticated()) {
      console.log(`[API] ${config.method?.toUpperCase()} ${config.url}`);
    }

    const token = localStorage.getItem('authToken');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }

    return config;
  },
  (error) => Promise.reject(error)
);

// Response interceptor - handle 401 errors
api.interceptors.response.use(
  (response) => response,
  (error) => {
    // Silently ignore aborted unauthenticated requests
    if (axios.isCancel(error) || error.message === "Unauthenticated") {
      return Promise.reject(error);
    }

    if (error.response?.status === 401) {
      const isAuthRequest = isPublicEndpoint(error.config?.url) ||
        error.config?.url?.includes('/auth/me'); // Don't redirect on check-me

      const isLoginPage = window.location.pathname === '/login' ||
        window.location.pathname === '/signup' ||
        window.location.pathname === '/onboarding';

      if (!isAuthenticated()) {
        // Silently ignore 401 if user not logged in
        return Promise.reject(error);
      }

      if (!isAuthRequest && !isLoginPage) {
        localStorage.removeItem('user');
        localStorage.removeItem('authToken');
        window.location.href = '/login';
      }
    }

    // Don't log 404s for optional endpoints (notifications, etc.)
    if (error.response?.status === 404) {
      const optionalEndpoints = ['/notifications/', '/api/v1/notifications'];
      const isOptional = optionalEndpoints.some(ep => error.config?.url?.includes(ep));

      if (isOptional) {
        // Return a successful response with fallback data
        return Promise.resolve({
          data: { success: false, warning: 'Endpoint not available' }
        });
      }
    }

    return Promise.reject(error);
  }
);

// Auth API
export const authAPI = {
  signup: (data) => api.post('/api/v1/auth/signup', data),
  login: (data) => api.post('/api/v1/auth/login', data),
  logout: () => api.post('/api/v1/auth/logout'),
  me: () => api.get('/api/v1/auth/me'),
  googleUrl: (params) => {
    const query = new URLSearchParams(params).toString();
    return `${API_URL}/auth/google${query ? `?${query}` : ''}`;
  },
  // Email verification
  resendVerification: (email) => api.post('/api/v1/resend_verification', { email }),
  verifyEmail: (token) => api.post('/api/v1/verify_email', { token }),
  getVerificationStatus: () => api.get('/api/v1/verification_status'),
  forgotPassword: (email) => api.post('/api/v1/auth/forgot_password', { email }),
  resetPassword: (payload) => api.post('/api/v1/auth/reset_password', payload),
};

// User API
export const userAPI = {
  getProfile: () => api.get('/api/v1/users/me'),
  updateProfile: (data) => api.put('/api/v1/users/me', data),
  deleteAccount: () => api.delete('/api/v1/users/me'),
};

// Invoices API
export const invoicesAPI = {
  getAll: (params) => api.get('/api/v1/invoices', { params }),
  getById: (id) => api.get(`/api/v1/invoices/${id}`),
  scan: (formData) =>
    api.post('/api/v1/invoice_scans/scan', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  create: (formData) =>
    api.post('/api/v1/invoices', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  update: (id, data) => api.put(`/api/v1/invoices/${id}`, data),
  delete: (id) => api.delete(`/api/v1/invoices/${id}`),
  download: (id) => api.get(`/api/v1/invoices/${id}/download`, { responseType: 'blob' }),
  preview: (id) => api.get(`/api/v1/invoices/${id}/preview`, { responseType: 'blob' }),
  getStats: () => api.get('/api/v1/invoices/stats'),
  getDashboard: () => api.get('/api/v1/invoices/dashboard'),
  getOcrStatus: (id) => api.get(`/api/v1/invoices/${id}/ocr_status`),
  retryOcr: (id) => api.post(`/api/v1/invoices/${id}/retry_ocr`),
  export: () => api.get('/api/v1/invoices/export', { responseType: 'blob' }),
};

// Notifications API
export const notificationsAPI = {
  getAll: (params) => api.get('/api/v1/notifications', { params }),
  getUnreadCount: () => api.get('/api/v1/notifications/unread_count'),
  markAsRead: (id) => api.put(`/api/v1/notifications/${id}/mark_as_read`),
  markAllAsRead: () => api.put('/api/v1/notifications/mark_all_as_read'),
  delete: (id) => api.delete(`/api/v1/notifications/${id}`),
  clearAll: () => api.delete('/api/v1/notifications/clear_all'),
};

// Gmail API
export const gmailAPI = {
  getConnection: () => api.get('/api/v1/gmail/connection'),
  connect: () => api.post('/api/v1/gmail/connect'),
  sync: () => api.post('/api/v1/gmail/sync'),
  disconnect: () => api.delete('/api/v1/gmail/disconnect'),
  getSuggestions: () => api.get('/api/v1/gmail/suggestions'),
};

// User Reminder Preferences API
export const userReminderPreferencesAPI = {
  get: () => api.get('/api/v1/user_reminder_preferences'),
  create: (data) => api.post('/api/v1/user_reminder_preferences', data),
  delete: (id) => api.delete(`/api/v1/user_reminder_preferences/${id}`),
  toggleAlerts: (enabled) => api.post('/api/v1/user_reminder_preferences/toggle_alerts', { enabled }),
};

export default api;
