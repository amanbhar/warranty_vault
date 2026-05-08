import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import useInvoiceStore from '../store/invoiceStore';
import { Header } from '../components/Header';
import { Layout } from '../components/Layout';
import { Card } from '../components/Card';
import { Badge } from '../components/Badge';
import { Button } from '../components/Button';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function Timeline() {
  const navigate = useNavigate();
  const { invoices, refreshAllInvoiceData, loading } = useInvoiceStore();

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

  if (loading) {
    return <LoadingSpinner />;
  }

  const formatDate = (dateString) => {
    if (!dateString) return 'N/A';
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      day: 'numeric',
      month: 'short',
      year: 'numeric'
    });
  };

  const allWarranties = invoices.flatMap(invoice => 
    (invoice.items || []).flatMap(item => 
      (item.warranties || []).map(warranty => ({
        ...warranty,
        product_name: item.product_name,
        brand: item.brand,
        invoice_id: invoice.id
      }))
    )
  );

  const sortedWarranties = allWarranties.sort((a, b) => {
    if (!a.expires_at) return 1;
    if (!b.expires_at) return -1;
    return new Date(a.expires_at) - new Date(b.expires_at);
  });

  return (
    <Layout>
      <Header title="Warranty Timeline" />

      {/* Summary Card */}
      <Card className="mt-4 p-4 bg-primary/5 border-primary/10">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
              Total Coverage Value
            </p>
            <p className="text-2xl font-bold text-primary mt-1">
              ₨. {invoices.reduce((sum, i) => sum + (parseFloat(i.total_amount) || 0), 0).toFixed(2)}
            </p>
          </div>
          <div className="bg-primary text-white p-3 rounded-lg">
            <span className="material-symbols-outlined">account_balance_wallet</span>
          </div>
        </div>
      </Card>

        {/* Timeline */}
        <div className="mt-8 space-y-0 relative">
          {sortedWarranties.length > 0 ? (
            sortedWarranties.map((warranty, index) => (
              <div key={`${warranty.id}-${index}`} className="flex flex-col">
                <div
                  className="grid grid-cols-[48px_1fr] gap-x-3 cursor-pointer group"
                  onClick={() => navigate(`/invoice/${warranty.invoice_id}`)}
                >
                  <div className="flex flex-col items-center">
                    <div className={`flex h-12 w-12 items-center justify-center rounded-full border-4 border-white dark:border-background-dark shadow-sm z-10 transition-transform group-hover:scale-110 ${warranty.status === 'active' ? 'bg-green-100 dark:bg-green-900/40 text-green-600' :
                        warranty.status === 'expiring' ? 'bg-amber-100 dark:bg-amber-900/40 text-amber-600' :
                          'bg-red-100 dark:bg-red-900/40 text-red-600'
                      }`}>
                      <span className="material-symbols-outlined text-2xl font-black">
                        {warranty.status === 'active' ? 'verified' :
                          warranty.status === 'expiring' ? 'priority_high' :
                            'cancel'}
                      </span>
                    </div>
                    {index < sortedWarranties.length - 1 && (
                      <div className="w-0.5 bg-slate-200 dark:bg-slate-700 h-full -mt-2"></div>
                    )}
                  </div>

                  <div className="flex flex-1 flex-col pb-8 pt-1">
                    <div className="flex justify-between items-start">
                      <div className="flex-1 pr-2">
                        <p className="text-[15px] font-black leading-tight text-slate-900 dark:text-slate-100 mb-1">
                          {warranty.product_name}
                        </p>
                        <p className="text-[11px] font-bold uppercase tracking-widest text-primary mb-2">
                          {warranty.component_display || warranty.component} Coverage
                        </p>
                        <div className="flex flex-col">
                          <p className={`text-xs font-bold leading-none mb-1 ${warranty.status === 'expiring'
                              ? 'text-amber-600 dark:text-amber-400'
                              : 'text-slate-500 dark:text-slate-400'
                            }`}>
                            {warranty.status === 'expired'
                              ? `Expired ${Math.abs(warranty.days_remaining)} days ago`
                              : `${warranty.days_remaining} days remaining`
                            }
                          </p>
                          <p className="text-[11px] font-medium text-slate-400 flex items-center gap-1">
                            <span className="material-symbols-outlined text-[12px]">calendar_today</span>
                            Exp: {formatDate(warranty.expires_at)}
                          </p>
                        </div>
                      </div>
                      <Badge status={warranty.status === 'expiring' ? 'expiring_soon' : warranty.status} className="shrink-0" />
                    </div>
                  </div>
                </div>
              </div>
            ))
          ) : (
            <div className="text-center py-20">
              <span className="material-symbols-outlined text-6xl text-slate-200">inventory_2</span>
              <p className="text-slate-400 mt-4 font-bold">No active warranties found</p>
            </div>
          )}
        </div>
    </Layout>
  );
}
