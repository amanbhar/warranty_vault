import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { invoicesAPI } from '../services/api';
import { getDefaultProductImage } from '../utils/productImageHelper';
import useInvoiceStore from '../store/invoiceStore';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { Header } from '../components/Header';
import { Layout } from '../components/Layout';
import { Card } from '../components/Card';
import { Badge } from '../components/Badge';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { Alert } from '../components/Alert';
import { cn } from '../utils/cn';
import { monthsToYearsAndMonths } from '../utils/warrantyDurationHelper';

export function ProductDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  // const { fetchInvoice, loading: storeLoading } = useInvoiceStore();
  const { fetchInvoice, deleteInvoice } = useInvoiceStore();

  const [invoice, setInvoice] = useState(null);
  const [enrichment, setEnrichment] = useState({ image_url: null, description: null, loading: false });
  const [activeTab, setActiveTab] = useState('overview');
  const [loading, setLoading] = useState(true);
  const [showConfirmDelete, setShowConfirmDelete] = useState(false);
  const [deleteError, setDeleteError] = useState(null);
  const [deleting, setDeleting] = useState(false);

  // Resolve relative file URLs to absolute
  const apiBase = import.meta.env.VITE_API_URL || 'http://localhost:3005';

  const resolveFileUrl = (url) => {
    if (!url) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return `${apiBase}${url}`;
  };

  const invoiceFileUrl = resolveFileUrl(invoice?.file_url);

  useEffect(() => {
    const loadData = async () => {
      // Only load if we have a valid ID
      if (!id || id === 'undefined') {
        console.error('Invalid invoice ID:', id);
        navigate('/dashboard');
        return;
      }

      setLoading(true);
      const data = await fetchInvoice(id);
      if (data) {
        setInvoice(data);
        // Always pass through helper to resolve local assets even if URL is present in DB
        const resolvedImage = getDefaultProductImage(data.product_name, data.brand, data.product_image_url, data.category);

        setEnrichment({
          image_url: resolvedImage,
          description: data.description || '',
          loading: false
        });
      } else {
        // Invoice not found, redirect to dashboard
        console.error('Invoice not found for ID:', id);
        navigate('/dashboard');
      }
      setLoading(false);
    };
    loadData();
  }, [id, navigate]);


  useEffect(() => {
    if (!id) return;

    const onProductUpdate = async () => {
      const data = await fetchInvoice(id);
      if (!data) return;

      setInvoice(data);
      const resolvedImage = getDefaultProductImage(data.product_name, data.brand, data.product_image_url, data.category);
      setEnrichment({
        image_url: resolvedImage,
        description: data.description || '',
        loading: false,
      });
    };

    window.addEventListener('products:updated', onProductUpdate);
    return () => window.removeEventListener('products:updated', onProductUpdate);
  }, [id, fetchInvoice]);


  const handleDownload = async () => {
    if (!invoice?.id || !invoice?.has_file) return;
    try {
      const response = await invoicesAPI.download(invoice.id);
      const url = window.URL.createObjectURL(new Blob([response.data]));
      const link = document.createElement('a');
      link.href = url;
      link.setAttribute('download', invoice.original_filename || `invoice-${invoice.id}.pdf`);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Download failed:', error);
    }
  };

  const handleDeleteClick = () => {
    if (!invoice?.id) return;
    setDeleteError(null);
    setShowConfirmDelete(true);
  };

  const handleDeleteConfirm = async () => {
    setDeleting(true);
    const result = await deleteInvoice(invoice.id);
    setDeleting(false);
    if (result.success) {
      navigate('/dashboard');
    } else {
      setDeleteError(result.error || 'Delete failed. Please try again.');
      setShowConfirmDelete(false);
    }
  };

  const handleDeleteCancel = () => {
    setShowConfirmDelete(false);
    setDeleteError(null);
  };

  const handleViewInvoice = () => {
    if (invoiceFileUrl) {
      window.open(invoiceFileUrl, '_blank', 'noopener,noreferrer');
      return;
    }

    // Fallback for older records where file_url is unavailable.
    window.open(`${apiBase}/api/v1/invoices/${invoice.id}/preview`, '_blank', 'noopener,noreferrer');
  };

  if (loading || !invoice) {
    return <LoadingSpinner />;
  }

  const tabs = [
    { id: 'overview', label: 'Overview', icon: 'info' },
    { id: 'warranty', label: 'Warranty', icon: 'verified_user' },
    { id: 'invoice', label: 'Invoice', icon: 'description' },
  ];

  return (
    <Layout className="pb-32">
      <Header title="Product Details" showBack />

      {/* Product Hero */}
      <div className="relative group">
        <div className="w-full aspect-[4/3] rounded-3xl overflow-hidden bg-slate-100 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 shadow-lg transition-all duration-500 group-hover:shadow-xl">
          {enrichment.image_url ? (
            <>
              <img
                src={enrichment.image_url}
                alt={invoice.product_name}
                className="w-full h-full object-cover"
                onLoad={() => console.log('[ProductDetail] Image loaded successfully:', enrichment.image_url)}
                onError={(e) => console.error('[ProductDetail] Image failed to load:', e, enrichment.image_url)}
              />
            </>
          ) : (
            <div className="w-full h-full flex flex-col items-center justify-center text-slate-300 dark:text-slate-600">
              <span className="material-symbols-outlined text-8xl">shopping_bag</span>
              <p className="text-sm mt-2 font-medium">No image available</p>
            </div>
          )}
          {/* Action Overlay */}
          <div className="absolute top-4 right-4 z-20 flex gap-3">
            <div className="flex flex-col items-center gap-2">
              <button
                onClick={() => navigate(`/invoice/${invoice.id}/edit`)}
                className="size-12 rounded-full bg-blue-500 hover:bg-blue-600 backdrop-blur-md text-white shadow-lg shadow-blue-500/30 border-2 border-blue-400/50 flex items-center justify-center transition-all duration-300 hover:scale-110 hover:shadow-xl hover:shadow-blue-500/40 animate-pulse-slow"
                title="Edit Product"
              >
                <span className="material-symbols-outlined text-2xl">edit</span>
              </button>
              <span className="text-xs font-bold text-blue-500 bg-white/90 dark:bg-slate-900/90 px-2 py-1 rounded-lg shadow-sm backdrop-blur-sm">Edit</span>
            </div>
            <div className="flex flex-col items-center gap-2">
              <button
                onClick={handleDeleteClick}
                className="size-12 rounded-full bg-rose-500 hover:bg-rose-600 backdrop-blur-md text-white shadow-lg shadow-rose-500/30 border-2 border-rose-400/50 flex items-center justify-center transition-all duration-300 hover:scale-110 hover:shadow-xl hover:shadow-rose-500/40 animate-pulse-slow"
                title="Delete"
              >
                <span className="material-symbols-outlined text-2xl">delete</span>
              </button>
              <span className="text-xs font-bold text-rose-500 bg-white/90 dark:bg-slate-900/90 px-2 py-1 rounded-lg shadow-sm backdrop-blur-sm">Delete</span>
            </div>
          </div>
          {/*<div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-500"></div>*/}
          <div className="absolute inset-0 pointer-events-none bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-500"></div>
        </div>

        <div className="absolute bottom-6 left-6 right-6 text-white opacity-0 group-hover:opacity-100 transition-all duration-500 translate-y-4 group-hover:translate-y-0">
          <h2 className="text-2xl font-bold truncate">{invoice.product_name}</h2>
          <p className="text-sm opacity-90">{invoice.brand} {invoice.model_number ? ` • ${invoice.model_number}` : ''}</p>
        </div>
      </div>

      {/* Action Bar */}
      <div className="mt-8 flex items-center justify-between">
        <div className="flex-1">
          <h2 className="text-2xl font-bold text-slate-900 dark:text-slate-100 truncate">
            {invoice.product_name}
          </h2>
          <p className="text-sm text-slate-500 dark:text-slate-400 mt-1 flex items-center gap-2">
            <span className="font-bold text-slate-700 dark:text-slate-300">{invoice.brand}</span>
            {invoice.model_number && (
              <>
                <span className="size-1 rounded-full bg-slate-300"></span>
                <span>{invoice.model_number}</span>
              </>
            )}
          </p>
        </div>
        <Badge status={invoice.warranty_status} />
      </div>

      {/* Custom Tabs */}
      <div className="mt-8 bg-white dark:bg-slate-900 rounded-2xl p-1 shadow-sm border border-slate-100 dark:border-slate-800 flex">
        {tabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={cn(
              "flex-1 flex items-center justify-center gap-2 py-3 rounded-xl text-sm font-bold transition-all duration-300",
              activeTab === tab.id
                ? "bg-primary text-white shadow-md shadow-primary/20 scale-[1.02]"
                : "text-slate-500 hover:text-slate-700 dark:hover:text-slate-300"
            )}
          >
            <span className="material-symbols-outlined text-xl">{tab.icon}</span>
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab Content */}
      <div className="mt-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
        {activeTab === 'overview' && (
          <div className="space-y-6">
            {enrichment.description && (
              <Card className="p-6 overflow-hidden relative">
                <div className="absolute top-0 left-0 w-1 h-full bg-primary/20"></div>
                <h3 className="text-sm font-bold text-slate-400 uppercase tracking-widest mb-3">About Product</h3>
                <p className="text-slate-600 dark:text-slate-300 leading-relaxed text-sm italic">
                  "{enrichment.description}"
                </p>
              </Card>
            )}

            <Card className="divide-y divide-slate-50 dark:divide-slate-800">
              <div className="p-4 flex justify-between items-center">
                <span className="text-sm font-medium text-slate-500">Retailer</span>
                <span className="text-sm font-bold text-slate-900 dark:text-slate-100">{invoice.seller_name || 'N/A'}</span>
              </div>
              <div className="p-4 flex justify-between items-center">
                <span className="text-sm font-medium text-slate-500">Price Paid</span>
                <span className="text-sm font-bold text-primary">{invoice.formatted_amount || 'N/A'}</span>
              </div>
              <div className="p-4 flex justify-between items-center">
                <span className="text-sm font-medium text-slate-500">Purchase Date</span>
                <span className="text-sm font-bold text-slate-900 dark:text-slate-100">
                  {invoice.purchase_date ? new Date(invoice.purchase_date).toLocaleDateString(undefined, { dateStyle: 'long' }) : 'N/A'}
                </span>
              </div>
              <div className="p-4 flex justify-between items-center">
                <span className="text-sm font-medium text-slate-500">Category</span>
                <span className="text-sm font-bold text-slate-900 dark:text-slate-100">{invoice.category || 'General'}</span>
              </div>
            </Card>
          </div>
        )}

        {activeTab === 'warranty' && (
          <div className="space-y-4">
            {/* Warranty Overview Card */}
            <Card className="p-6 bg-gradient-to-br from-primary to-blue-700 text-white border-none">
              <div className="flex justify-between items-start">
                <div>
                  <p className="text-primary-foreground/70 text-xs font-bold uppercase tracking-widest">Overall Status</p>
                  <h3 className="text-3xl font-black mt-1 capitalize">
                    {invoice.invoice_status || invoice.warranty_status || 'N/A'}
                  </h3>
                </div>
                <div className="size-12 rounded-2xl bg-white/20 backdrop-blur-md flex items-center justify-center">
                  <span className="material-symbols-outlined text-2xl">verified</span>
                </div>
              </div>
              <p className="mt-4 text-sm font-medium opacity-90">
                {invoice.items?.reduce((sum, item) => sum + (item.warranties?.length || 0), 0) || 0} warranty coverage(s) tracked
                across {invoice.items?.length || 0} product(s).
              </p>
            </Card>

            {/* Items Breakdown */}
            {invoice.items?.map((item, itemIdx) => (
              <div key={item.id || itemIdx} className="mt-8 border-t border-slate-100 dark:border-slate-800 pt-6 first:border-t-0 first:pt-0">
                <div className="flex gap-4 items-start mb-4">
                  <div className="size-20 rounded-2xl bg-slate-100 dark:bg-slate-800 overflow-hidden shrink-0 border border-slate-200 dark:border-slate-700 shadow-sm">
                    <img
                      src={getDefaultProductImage(item.product_name, item.brand, item.product_image_url, item.category)}
                      alt={item.product_name}
                      className="w-full h-full object-cover"
                    />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex justify-between items-start">
                      <h3 className="text-lg font-bold text-slate-900 dark:text-slate-100 truncate">
                        {item.product_name}
                      </h3>
                      <span className={cn(
                        "text-[10px] font-black uppercase px-2 py-0.5 rounded shrink-0 ml-2",
                        item.item_status === 'active' ? "bg-emerald-100 text-emerald-700" :
                          item.item_status === 'expired' ? "bg-rose-100 text-rose-700" : "bg-amber-100 text-amber-700"
                      )}>
                        {item.item_status}
                      </span>
                    </div>
                    <p className="text-sm text-slate-500 font-medium">{item.brand || 'No Brand'}</p>
                  </div>
                </div>

                <div className="space-y-3 mt-3">
                  {item.warranties?.length > 0 ? (
                    item.warranties.map((w, idx) => {
                      const iconMap = {
                        compressor: 'autostop',
                        battery: 'battery_charging_full',
                        panel: 'window',
                        motor: 'settings',
                        screen: 'phone_android',
                        parts: 'build',
                        labour: 'engineering',
                        accessories: 'cable',
                        handset: 'smartphone',
                        product: 'verified_user',
                      };
                      const icon = iconMap[w.component?.toLowerCase()] || 'verified_user';

                      const isExpired = w.status === 'expired' || w.days_remaining <= 0;
                      const isExpiring = w.status === 'expiring';

                      let progressPct = 0;
                      if (w.duration_months && w.expires_at) {
                        const totalDays = w.duration_months * 30.44;
                        const daysElapsed = totalDays - (w.days_remaining || 0);
                        progressPct = Math.min(100, Math.max(0, (daysElapsed / totalDays) * 100));
                      }

                      return (
                        <Card key={`${w.id || idx}`} className="p-4 hover:shadow-md transition-shadow">
                          <div className="flex items-center gap-4">
                            <div className={cn(
                              "size-12 rounded-2xl flex items-center justify-center shrink-0",
                              isExpired ? "bg-rose-50 text-rose-600" :
                              isExpiring ? "bg-amber-50 text-amber-600" : "bg-emerald-50 text-emerald-600"
                            )}>
                              <span className="material-symbols-outlined text-2xl">{icon}</span>
                            </div>
                            <div className="flex-1 min-w-0">
                              <div className="flex justify-between items-start">
                                <h4 className="font-bold text-slate-900 dark:text-slate-100 truncate capitalize">
                                  {w.component_display || w.component || 'Warranty'}
                                </h4>
                                <span className={cn(
                                  "text-[10px] font-bold px-2 py-0.5 rounded-full",
                                  isExpired ? "bg-rose-100 text-rose-600" :
                                  isExpiring ? "bg-amber-100 text-amber-600" : "bg-emerald-100 text-emerald-600"
                                )}>
                                  {isExpired ? 'Expired' : isExpiring ? `${w.days_remaining}d left` : `${w.days_remaining}d left`}
                                </span>
                              </div>
                              <div className="flex items-center gap-3 mt-1">
                                <p className="text-xs text-slate-500">
                                  {w.duration_display || monthsToYearsAndMonths(w.duration_months).display}
                                </p>
                                <span className="size-1 rounded-full bg-slate-200" />
                                <p className="text-xs text-slate-500">
                                  Exp: {w.expires_at ? new Date(w.expires_at).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : 'N/A'}
                                </p>
                              </div>
                              <div className="mt-2 h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden">
                                <div
                                  className={cn(
                                    "h-full rounded-full transition-all",
                                    isExpired ? "bg-rose-400" : isExpiring ? "bg-amber-400" : "bg-emerald-400"
                                  )}
                                  style={{ width: `${progressPct}%` }}
                                />
                              </div>
                            </div>
                          </div>
                        </Card>
                      );
                    })
                  ) : (
                    <Card className="p-4 text-center border-dashed">
                      <span className="material-symbols-outlined text-3xl text-slate-300 block mb-2">verified_user</span>
                      <p className="text-slate-400 text-xs">No warranty details found for this product.</p>
                      <p className="text-slate-400 text-xs mt-1">Edit the product to add warranty information.</p>
                    </Card>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {activeTab === 'invoice' && (
          <div className="space-y-4">
            <Card className="p-0 overflow-hidden">
              <div className="bg-slate-50 dark:bg-slate-800 p-6 flex items-center justify-between border-b border-slate-100 dark:border-slate-700">
                <div className="flex items-center gap-4">
                  <div className="size-14 bg-white dark:bg-slate-900 rounded-2xl shadow-sm flex items-center justify-center text-primary">
                    <span className="material-symbols-outlined text-3xl">picture_as_pdf</span>
                  </div>
                  <div>
                    <h4 className="font-bold text-slate-900 dark:text-slate-100">Original Invoice</h4>
                    <p className="text-xs text-slate-500 uppercase tracking-tighter mt-0.5">
                      {invoice.original_filename || 'receipt.pdf'}
                    </p>
                  </div>
                </div>
                <Button onClick={handleDownload} className="shrink-0 p-3" disabled={!invoice?.has_file}>
                  <span className="material-symbols-outlined">download</span>
                </Button>
              </div>

              <div className="p-6">
                <div className="w-full aspect-video rounded-xl bg-slate-100 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 flex items-center justify-center relative overflow-hidden group">
                  <span className="material-symbols-outlined text-6xl text-slate-300 group-hover:scale-110 transition-transform duration-500">visibility</span>
                  <div className="absolute inset-0 bg-white/40 dark:bg-black/40 backdrop-blur-[2px] opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                    <Button onClick={handleViewInvoice} variant="secondary" disabled={!invoice?.has_file}>
                      View Full Document
                    </Button>
                  </div>
                </div>
              </div>
            </Card>
          </div>
        )}
      </div>

      {/* Delete Error Banner */}
      {deleteError && (
        <div className="fixed top-6 left-1/2 -translate-x-1/2 z-50 bg-rose-500 text-white px-5 py-3 rounded-2xl shadow-xl text-sm font-bold flex items-center gap-3">
          <span className="material-symbols-outlined text-lg">error</span>
          {deleteError}
          <button onClick={() => setDeleteError(null)} className="ml-2 text-white/70 hover:text-white">✕</button>
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {showConfirmDelete && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 bg-black/60 backdrop-blur-sm">
          <div className="bg-white dark:bg-slate-900 rounded-3xl shadow-2xl p-7 max-w-sm w-full animate-in fade-in zoom-in-95 duration-200">
            <div className="flex flex-col items-center text-center gap-4">
              <div className="size-16 rounded-full bg-rose-100 dark:bg-rose-900/40 flex items-center justify-center">
                <span className="material-symbols-outlined text-3xl text-rose-500">delete_forever</span>
              </div>
              <div>
                <h3 className="text-xl font-black text-slate-900 dark:text-slate-100">Delete Product?</h3>
                <p className="mt-2 text-sm text-slate-500 dark:text-slate-400 leading-relaxed">
                  This will permanently remove <span className="font-bold text-slate-700 dark:text-slate-300">{invoice?.product_name}</span> and all its warranty data. This action cannot be undone.
                </p>
              </div>
              <div className="flex gap-3 w-full mt-2">
                <button
                  onClick={handleDeleteCancel}
                  disabled={deleting}
                  className="flex-1 py-3 rounded-2xl border-2 border-slate-200 dark:border-slate-700 font-bold text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  onClick={handleDeleteConfirm}
                  disabled={deleting}
                  className="flex-1 py-3 rounded-2xl bg-rose-500 hover:bg-rose-600 font-bold text-white transition-colors disabled:opacity-70 flex items-center justify-center gap-2"
                >
                  {deleting ? (
                    <>
                      <span className="size-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Deleting...
                    </>
                  ) : (
                    'Yes, Delete'
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </Layout>
  );
}
