import { useEffect, useState, useRef } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import useAuthStore from '../store/authStore';
import useInvoiceStore from '../store/invoiceStore';
import { Header } from '../components/Header';
import { Layout } from '../components/Layout';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { cn } from '../utils/cn';
import { getDefaultProductImage } from '../utils/productImageHelper';
import { monthsToYearsAndMonths } from '../utils/warrantyDurationHelper';
import cable from '../cable';

/* ── Helpers ──────────────────────────────────────────────────────────────── */
function categoryIcon(cat) {
  const map = {
    electronics: 'laptop_mac',
    appliances: 'home_appliance',
    furniture: 'chair',
    tools: 'handyman',
    sports: 'fitness_center',
    clothing: 'checkroom',
  };
  return map[(cat || '').toLowerCase()] || 'inventory_2';
}

function categoryColor(cat) {
  const map = {
    electronics: 'from-blue-500 to-indigo-600',
    appliances: 'from-emerald-500 to-teal-600',
    furniture: 'from-amber-500 to-orange-500',
    tools: 'from-slate-500 to-slate-700',
    sports: 'from-rose-500 to-pink-600',
    clothing: 'from-purple-500 to-violet-600',
  };
  return map[(cat || '').toLowerCase()] || 'from-primary to-blue-600';
}

function warrantyLabel(status, daysRemaining) {
  if (status === 'active' && daysRemaining != null) {
    if (daysRemaining > 365) {
      const years = Math.floor(daysRemaining / 365);
      return `${years} yr${years > 1 ? 's' : ''} left`;
    }
    if (daysRemaining > 30) {
      const months = Math.floor(daysRemaining / 30);
      return `${months} mo left`;
    }
    return `${daysRemaining} days left`;
  }
  if (status === 'expiring_soon') return 'Expiring soon!';
  if (status === 'expired') return 'Expired';
  return 'Unknown';
}

function statusDot(status) {
  const colors = {
    active: 'bg-emerald-400',
    expiring: 'bg-amber-400',
    expired: 'bg-rose-400',
  };
  return colors[status] || 'bg-slate-400';
}

function formatDate(dateStr) {
  if (!dateStr) return 'N/A';
  return new Date(dateStr).toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
  });
}

/* ── Sub-components ───────────────────────────────────────────────────────── */
function SummaryPill({ label, value, color }) {
  return (
    <div className="flex-1 bg-white dark:bg-slate-900 rounded-2xl p-4 border border-slate-100 dark:border-slate-800 shadow-sm flex flex-col items-center gap-1">
      <span className={`text-2xl font-bold ${color}`}>{value}</span>
      <span className="text-[10px] font-semibold tracking-widest uppercase text-slate-400">{label}</span>
    </div>
  );
}

function WarrantyProgressBar({ item }) {
  const { nearest_expiry_date, item_status } = item;
  if (!nearest_expiry_date) return null;

  // Since we don't have start_date easily here for the progress bar at item level 
  // without more data, we might just hide it or use a simplified version.
  // Requirement says "nearest expiry date" for card, doesn't explicitly mention progress bar.
  // But let's keep it if we can. Actually we have start_date in warranties.
  
  return null; 
}

function ProductCard({ item, onClick, invoiceId }) {
  const { item_status, nearest_expiry_date, product_name, brand, product_image_url, category } = item;

  const badgeStyles = {
    active: 'bg-emerald-50 text-emerald-600 border-emerald-100',
    expiring: 'bg-amber-50 text-amber-600 border-amber-100',
    expired: 'bg-rose-50 text-rose-500 border-rose-100',
  };

  return (
    <button
      onClick={onClick}
      className="w-full text-left bg-white dark:bg-slate-900 rounded-2xl border border-slate-100 dark:border-slate-800 shadow-sm hover:shadow-md hover:-translate-y-0.5 transition-all duration-200 overflow-hidden focus:outline-none focus:ring-2 focus:ring-primary/30"
    >
      {/* Card image area */}
      <div className="relative h-32 bg-slate-100 dark:bg-slate-800 flex items-center justify-center overflow-hidden">
        <img
          src={getDefaultProductImage(product_name, brand, product_image_url, category)}
          alt={product_name}
          className="w-full h-full object-cover"
        />

        {/* Status badge top-right */}
        <span className={`absolute top-3 right-3 text-[10px] font-bold px-2 py-0.5 rounded-full border shadow-sm backdrop-blur-md ${badgeStyles[item_status] || badgeStyles.active}`}>
          {item_status === 'active' ? '✓ Active' : item_status === 'expiring' ? '⚠ Expiring' : '✕ Expired'}
        </span>
      </div>

      {/* Card body */}
      <div className="p-4">
        <h4 className="font-bold text-slate-900 dark:text-slate-100 text-sm leading-tight truncate">
          {product_name || 'Scanning…'}
        </h4>
        {brand && (
          <p className="text-xs text-slate-400 mt-0.5 truncate">{brand}</p>
        )}

        <div className="mt-3 flex items-center justify-between">
          <div className="flex items-center gap-1.5">
            <span className={`inline-block size-2 rounded-full ${statusDot(item_status)}`} />
            <span className="text-xs font-medium text-slate-600 dark:text-slate-300 capitalize">
              {item_status}
            </span>
          </div>
          <span className="text-xs text-slate-400">{formatDate(nearest_expiry_date)}</span>
        </div>
      </div>
    </button>
  );
}

function ExpiryCard({ item }) {
  const urgency = item.days_remaining <= 7
    ? 'border-l-rose-500 bg-rose-50 dark:bg-rose-900/10'
    : 'border-l-amber-400 bg-amber-50 dark:bg-amber-900/10';

  return (
    <div className={`border-l-4 ${urgency} rounded-r-xl p-3`}>
      <div className="flex justify-between items-start">
        <div>
          <p className="text-xs font-bold text-slate-800 dark:text-slate-200 truncate">
            {item.product_name}
          </p>
          <p className="text-[11px] text-slate-500 mt-0.5">
            {item.component_display} · {item.duration_display || monthsToYearsAndMonths(item.duration_months).display} warranty
          </p>
        </div>
        <span className="text-[11px] font-bold text-amber-600 whitespace-nowrap ml-2">
          {item.days_remaining}d left
        </span>
      </div>
    </div>
  );
}

/* ── Main Dashboard ───────────────────────────────────────────────────────── */
export function Dashboard() {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, setToken, login } = useAuthStore();
  const {
    stats, invoices, dashboard,
    fetchStats, fetchInvoices, fetchDashboard, refreshAllInvoiceData, loading, refreshing, set,
  } = useInvoiceStore();

  const [searchQuery, setSearchQuery] = useState('');
  const [filter, setFilter] = useState('all'); // all | active | expiring | expired
  const { deleteInvoice } = useInvoiceStore();

  // Handle auto-login from verification email
  useEffect(() => {
    const params = new URLSearchParams(location.search);
    const token = params.get('token');
    const verified = params.get('verified') === 'true';

    if (token && verified) {
      handleAutoLogin(token);
    }
  }, [location]);

  const handleAutoLogin = async (token) => {
    try {
      // Set token in localStorage
      setToken(token);

      // Verify token and get user data
      const response = await fetch('/api/v1/auth/me', {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        credentials: 'include'
      });

      if (response.ok) {
        const userData = await response.json();
        login({ token, user: userData });

        // Clean URL to remove token parameters
        window.history.replaceState({}, document.title, '/dashboard');
      }
    } catch (error) {
      console.error('Auto-login failed:', error);
      navigate('/login');
    }
  };

  useEffect(() => {
    // Only fetch data if user is authenticated
    if (user) {
      console.log('[Dashboard] Fetching data for user:', user.id);
      refreshAllInvoiceData({ per_page: 20 }).then(() => {
        console.log('[Dashboard] Data fetched:', { stats, invoices, dashboard });
      }).catch((error) => {
        console.error('[Dashboard] Failed to fetch data:', error);
      });
    }
  }, [user, refreshAllInvoiceData]);

  // Subscribe to dashboard updates via WebSocket
  useEffect(() => {
    if (!user) return;

    const subscription = cable.subscriptions.create(
      { channel: 'DashboardChannel' },
      {
        connected: () => {
          console.log('[Dashboard] Connected to WebSocket');
        },
        disconnected: () => {
          console.log('[Dashboard] Disconnected from WebSocket');
        },
        rejected: () => {
          console.error('[Dashboard] WebSocket subscription rejected');
        },
        received: (data) => {
          console.log('[Dashboard] Received update:', data);
          if (data.type === 'dashboard_update') {
            // Update dashboard data from WebSocket
            if (data.summary) {
              set((state) => ({
                stats: {
                  ...state.stats,
                  active: data.summary.active_warranties,
                  expiring_soon: data.summary.expiring_soon,
                  expired: data.summary.expired,
                  total: data.summary.total_invoices,
                  total_value: data.summary.total_value
                }
              }));
            }
            if (data.upcoming_expirations) {
              set((state) => ({
                dashboard: {
                  ...state.dashboard,
                  upcoming_expirations: data.upcoming_expirations
                }
              }));
            }
          }
        }
      }
    );

    return () => {
      subscription.unsubscribe();
    };
  }, [user, set]);


  const handleSearch = (e) => {
    e.preventDefault();
    if (searchQuery.trim()) navigate(`/search?q=${searchQuery}`);
  };

  const handleDeleteProduct = async (invoiceId) => {
    const result = await deleteInvoice(invoiceId);
    if (result.success) {
      // Refresh stats and dashboard data
      refreshAllInvoiceData({ per_page: 20 });
    }
  };

  // Flatten invoices into items
  const allItems = (invoices || []).flatMap(inv =>
    (inv.items || []).map(item => ({ ...item, invoiceId: inv.id }))
  );

  const filtered = filter === 'all'
    ? allItems
    : allItems.filter((item) => item.item_status === filter);

  const upcomingExpirations = dashboard?.upcoming_expirations || [];

  return (
    <Layout>
      <Header />

      {/* ── Greeting ────────────────────────────────────────────────── */}
      <div className="pt-6 pb-2">
        <h1 className="text-2xl font-bold text-slate-900 dark:text-slate-100 lg:text-3xl">
          Hey {user?.first_name || user?.email?.split('@')[0]} 👋
        </h1>
        <p className="text-sm text-slate-500 dark:text-slate-400 mt-0.5">
          {stats?.active || 0} active warranties tracked
        </p>
      </div>

        {/* ── Search ──────────────────────────────────────────────────── */}
        <form onSubmit={handleSearch} className="py-3">
          <div className="flex items-center gap-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-700 rounded-2xl px-4 h-12 shadow-sm lg:max-w-md">
            <span className="material-symbols-outlined text-slate-400 text-xl">search</span>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="flex-1 bg-transparent outline-none text-sm placeholder:text-slate-400 text-slate-900 dark:text-slate-100"
              placeholder="Search products, brands…"
            />
          </div>
        </form>

        {/* ── Summary Pills ────────────────────────────────────────────── */}
        <div className="flex gap-3 py-2">
          <SummaryPill label="Active" value={stats?.active || 0} color="text-emerald-500" />
          <SummaryPill label="Expiring" value={stats?.expiring_soon || 0} color="text-amber-500" />
          <SummaryPill label="Expired" value={stats?.expired || 0} color="text-rose-500" />
        </div>

        {/* ── Upcoming Expirations ─────────────────────────────────────── */}
        {/* {upcomingExpirations.length > 0 && (
          <section className="mt-5">
            <h3 className="text-sm font-bold text-slate-700 dark:text-slate-300 mb-3 flex items-center gap-2">
              <span className="material-symbols-outlined text-amber-500 text-base">schedule</span>
              Expiring Soon
            </h3>
            <div className="space-y-2">
              {upcomingExpirations.slice(0, 3).map((item) => (
                <button
                  key={item.id}
                  onClick={() => item.invoice_id && navigate(`/invoice/${item.invoice_id}`)}
                  className="w-full text-left"
                  disabled={!item.invoice_id}
                >
                  <ExpiryCard item={item} />
                </button>
              ))}
            </div>
          </section>
        )} */}

        {/* ── Filter Tabs ──────────────────────────────────────────────── */}
        <section className="mt-6">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-base font-bold text-slate-900 dark:text-slate-100">My Products</h3>
            <button
              onClick={() => navigate('/upload')}
              className="flex items-center gap-1 text-xs font-bold text-primary bg-primary/10 hover:bg-primary/20 px-3 py-1.5 rounded-full transition-colors"
            >
              <span className="material-symbols-outlined text-sm">add</span>
              Add
            </button>
          </div>

          {/* Filter chips */}
          <div className="flex gap-2 mb-4 overflow-x-auto no-scrollbar">
            {[
              { key: 'all', label: 'All' },
              { key: 'active', label: '✓ Active' },
              { key: 'expiring', label: '⚠ Expiring' },
              { key: 'expired', label: '✕ Expired' },
            ].map((f) => (
              <button
                key={f.key}
                onClick={() => setFilter(f.key)}
                className={`whitespace-nowrap text-xs font-semibold px-3 py-1.5 rounded-full border transition-all ${filter === f.key
                  ? 'bg-primary text-white border-primary'
                  : 'bg-white dark:bg-slate-900 text-slate-600 dark:text-slate-300 border-slate-200 dark:border-slate-700'
                  }`}
              >
                {f.label}
              </button>
            ))}
          </div>

          {/* ── Product Grid ───────────────────────────────────────────── */}
          {(loading || refreshing) && !allItems.length ? (
            <div className="flex justify-center py-10"><LoadingSpinner /></div>
          ) : filtered.length === 0 ? (
            <div className="bg-white dark:bg-slate-900 rounded-2xl border border-slate-100 dark:border-slate-800 p-10 text-center">
              <span className="material-symbols-outlined text-5xl text-slate-200 dark:text-slate-700 mb-3 block">
                inventory_2
              </span>
              <p className="text-sm text-slate-400 mb-4">No products yet</p>
              <button
                onClick={() => navigate('/upload')}
                className="btn-primary text-sm"
              >
                Upload First Invoice
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-4">
              {filtered.map((item, idx) => (
                <ProductCard
                  key={`${item.invoiceId}-${item.id || idx}`}
                  item={item}
                  invoiceId={item.invoiceId}
                  onClick={() => item.invoiceId && navigate(`/invoice/${item.invoiceId}`)}
                />
              ))}
            </div>
          )}
        </section>
    </Layout>
  );
}
