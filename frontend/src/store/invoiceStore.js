import { create } from 'zustand';
import { invoicesAPI, isAuthenticated } from '../services/api';

const useInvoiceStore = create((set, get) => ({
  invoices: [],
  stats: null,
  dashboard: null,
  loading: false,
  refreshing: false,
  pagination: { currentPage: 1, totalPages: 1, totalCount: 0 },

  // ── Fetch invoices list ────────────────────────────────────────────────────
  fetchInvoices: async (params = {}) => {
    set({ loading: true });
    try {
      const response = await invoicesAPI.getAll(params);
      console.log('[InvoiceStore] Invoices response:', response.data.invoices);
      set({ invoices: response.data.invoices, loading: false });
    } catch (error) {
      if (isAuthenticated()) {
        console.error('[InvoiceStore] Failed to fetch invoices:', error);
        console.error('[InvoiceStore] Error response:', error.response?.data);
      }
      set({ loading: false });
    }
  },

  // ── Fetch single invoice (with embedded product_warranties) ────────────────
  fetchInvoice: async (id) => {
    set({ loading: true });
    try {
      const response = await invoicesAPI.getById(id);
      set({ loading: false });
      // Backend returns the invoice directly at the root level, not wrapped
      return response.data.invoice || response.data;
    } catch (error) {
      if (isAuthenticated()) console.error('Failed to fetch invoice:', error);
      set({ loading: false });
      return null;
    }
  },

  // ── Create invoice (upload or manual) ─────────────────────────────────────
  scanInvoice: async (formData) => {
    set({ loading: true });
    try {
      const response = await invoicesAPI.scan(formData);
      set({ loading: false });
      return { 
        success: true, 
        data: response.data,
        missing_fields: response.data.missing_fields || [],
        warnings: response.data.warnings || []
      };
    } catch (error) {
      const errorData = error.response?.data || {};
      const payloadError = errorData.error;
      set({ loading: false });
      return {
        success: false,
        error: payloadError?.user_message || payloadError?.message || payloadError || 'Failed to scan invoice.',
        missing_fields: errorData.missing_fields || [],
        raw: error
      };
    }
  },

  createInvoice: async (formData) => {
    set({ loading: true });
    try {
      const response = await invoicesAPI.create(formData);
      const invoice = response.data.invoice;

      set((state) => ({
        invoices: [invoice, ...state.invoices],
        loading: false,
      }));

      return { success: true, invoice };
    } catch (error) {
      const message = error.response?.data?.error || 'Upload failed';
      set({ loading: false });
      return { success: false, error: message };
    }
  },

  // ── Update invoice ─────────────────────────────────────────────────────────
  updateInvoice: async (id, data) => {
    try {
      const response = await invoicesAPI.update(id, data);
      set((state) => ({
        invoices: state.invoices.map((i) => (i.id === id ? response.data.invoice : i)),
      }));
      await get().refreshAllInvoiceData();
      return { success: true, invoice: response.data.invoice };
    } catch (error) {
      const message = error.response?.data?.error || 'Update failed';
      return { success: false, error: message };
    }
  },

  // ── Delete invoice ─────────────────────────────────────────────────────────
  deleteInvoice: async (id) => {
    try {
      await invoicesAPI.delete(id);
      set((state) => ({ invoices: state.invoices.filter((i) => i.id !== id) }));
      return { success: true };
    } catch (error) {
      if (isAuthenticated()) console.error('Failed to delete invoice:', error);
      const message =
        error.response?.data?.error ||
        error.response?.data?.message ||
        `Delete failed${error.response?.status ? ` (HTTP ${error.response.status})` : ''}`;
      return { success: false, error: message };
    }
  },

  // ── Fetch stats ────────────────────────────────────────────────────────────
  fetchStats: async () => {
    try {
      const response = await invoicesAPI.getStats();
      set({ stats: response.data.stats });
    } catch (error) {
      if (isAuthenticated()) console.error('Failed to fetch stats:', error);
    }
  },

  // ── Fetch full dashboard data ──────────────────────────────────────────────
  fetchDashboard: async () => {
    try {
      const response = await invoicesAPI.getDashboard();
      console.log('[InvoiceStore] Dashboard response:', response.data);
      set({ dashboard: response.data.dashboard });
      // Also sync stats from dashboard summary
      const s = response.data.dashboard?.summary;
      if (s) {
        set({
          stats: {
            total: s.total_invoices,
            total_value: s.total_value,
            active: s.active_warranties,
            expiring_soon: s.expiring_soon,
            expired: s.expired,
          },
        });
      }
    } catch (error) {
      if (isAuthenticated()) {
        console.error('[InvoiceStore] Failed to fetch dashboard:', error);
        console.error('[InvoiceStore] Error response:', error.response?.data);
      }
    }
  },

  refreshAllInvoiceData: async (params = { per_page: 20 }) => {
    set({ refreshing: true });
    try {
      await Promise.all([
        get().fetchInvoices(params),
        get().fetchStats(),
        get().fetchDashboard(),
      ]);
    } finally {
      set({ refreshing: false });
    }
  },

  // ── Poll OCR status until complete ────────────────────────────────────────
  pollOcrStatus: async (id, onUpdate, maxAttempts = 30) => {
    let attempts = 0;
    const poll = async () => {
      try {
        const response = await invoicesAPI.getOcrStatus(id);
        const { ocr_status, extracted_fields } = response.data;
        onUpdate?.({ ocr_status, extracted_fields });

        if (ocr_status === 'completed' || ocr_status === 'failed') {
          return;
        }
        if (attempts < maxAttempts) {
          attempts++;
          await new Promise((r) => setTimeout(r, 3000));
          await poll();
        }
      } catch (e) {
        if (isAuthenticated()) console.error('[pollOcrStatus] error:', e);
      }
    };
    await poll();
  },

  // ── Search invoices ────────────────────────────────────────────────────────
  searchInvoices: async (query) => {
    set({ loading: true });
    try {
      const response = await invoicesAPI.getAll({ q: query });
      set({ invoices: response.data.invoices, loading: false });
    } catch (error) {
      if (isAuthenticated()) console.error('Search failed:', error);
      set({ loading: false });
    }
  },
}));

export default useInvoiceStore;
