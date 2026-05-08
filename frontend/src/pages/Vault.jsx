import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import useInvoiceStore from '../store/invoiceStore';
import { Header } from '../components/Header';
import { Layout } from '../components/Layout';
import { Card } from '../components/Card';
import { Badge } from '../components/Badge';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function Vault() {
  const navigate = useNavigate();
  const { invoices, refreshAllInvoiceData, loading } = useInvoiceStore();
  const [filterStatus, setFilterStatus] = useState('all');

  useEffect(() => {
    refreshAllInvoiceData({ per_page: 50 });

    const interval = setInterval(() => {
      refreshAllInvoiceData({ per_page: 50 });
    }, 30000);

    const onProductUpdate = () => refreshAllInvoiceData({ per_page: 50 });
    window.addEventListener('products:updated', onProductUpdate);

    return () => {
      clearInterval(interval);
      window.removeEventListener('products:updated', onProductUpdate);
    };
  }, [refreshAllInvoiceData]);

  function filteredItems() {
    // Flatten invoices into items
    const allItems = invoices.flatMap(inv => 
      (inv.items || []).map(item => ({ ...item, invoiceId: inv.id }))
    );

    let filtered = allItems;

    // Status filter
    if (filterStatus !== 'all') {
      filtered = filtered.filter(item => {
        if (filterStatus === 'active') return item.item_status === 'active';
        if (filterStatus === 'expiring') return item.item_status === 'expiring';
        if (filterStatus === 'expired') return item.item_status === 'expired';
        return true;
      });
    }

    return filtered;
  }

  if (loading && !invoices.length) {
    return <LoadingSpinner />;
  }

  return (
    <Layout>
      <Header title="My Vault" />

      {/* Filter Pills */}
      <div className="flex gap-2 overflow-x-auto no-scrollbar mt-4 mb-4">
        <button
          onClick={() => setFilterStatus('all')}
          className={`h-9 px-5 rounded-full text-sm font-semibold whitespace-nowrap ${filterStatus === 'all'
              ? 'bg-primary text-white'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400'
            }`}
        >
          All Items
        </button>
        <button
          onClick={() => setFilterStatus('active')}
          className={`h-9 px-5 rounded-full text-sm font-medium whitespace-nowrap ${filterStatus === 'active'
              ? 'bg-primary text-white'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400'
            }`}
        >
          Active
        </button>
        <button
          onClick={() => setFilterStatus('expiring')}
          className={`h-9 px-5 rounded-full text-sm font-medium whitespace-nowrap ${filterStatus === 'expiring'
              ? 'bg-primary text-white'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400'
            }`}
        >
          Expiring
        </button>
        <button
          onClick={() => setFilterStatus('expired')}
          className={`h-9 px-5 rounded-full text-sm font-medium whitespace-nowrap ${filterStatus === 'expired'
              ? 'bg-primary text-white'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400'
            }`}
        >
          Expired
        </button>
      </div>

        {/* Invoices List */}
        <div className="space-y-3">
          {filteredItems().length === 0 ? (
            <Card className="p-8 text-center">
              <span className="material-symbols-outlined text-4xl text-slate-300 mb-2">inventory_2</span>
              <p className="text-slate-500 dark:text-slate-400">
                {filterStatus !== 'all' ? 'No items found for this filter' : 'No items found'}
              </p>
              {filterStatus === 'all' && (
                <button
                  onClick={() => navigate('/upload')}
                  className="text-primary font-medium mt-2"
                >
                  Upload your first receipt
                </button>
              )}
            </Card>
          ) : (
            filteredItems().map((item, idx) => (
              <Card
                key={`${item.invoiceId}-${item.id || idx}`}
                className="p-4 flex flex-col sm:flex-row sm:items-center gap-4 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors"
                onClick={() => navigate(`/invoice/${item.invoiceId}`)}
              >
                {/* Item Info */}
                <div className="flex-1 min-w-0">
                  <h4 className="font-bold text-slate-900 dark:text-slate-100 truncate">
                    {item.product_name}
                  </h4>
                  <p className="text-sm text-slate-500 dark:text-slate-400">
                    {item.brand} • {item.price ? `₨. ${item.price}` : 'N/A'}
                  </p>
                  <div className="flex items-center text-xs text-slate-400 mt-1">
                    <span className="material-symbols-outlined text-xs mr-1">history</span>
                    Expires on {item.nearest_expiry_date ? new Date(item.nearest_expiry_date).toLocaleDateString() : 'N/A'}
                  </div>
                </div>
                <Badge status={item.item_status === 'expiring' ? 'expiring_soon' : item.item_status} />
              </Card>
            ))
          )}
        </div>
    </Layout>
  );
}
