import { useState, useEffect } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import useInvoiceStore from '../store/invoiceStore';
import { Layout } from '../components/Layout';
import { Card } from '../components/Card';
import { Badge } from '../components/Badge';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function Search() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const query = searchParams.get('q') || '';
  const { searchInvoices, invoices, loading } = useInvoiceStore();
  const [localQuery, setLocalQuery] = useState(query);

  useEffect(() => {
    if (query) {
      searchInvoices(query);
    }
  }, [query]);

  const handleSearch = (e) => {
    e.preventDefault();
    if (localQuery.trim()) {
      navigate(`/search?q=${localQuery}`);
    }
  };

  return (
    <Layout>
      {/* Sticky Header */}
      <div className="sticky top-0 z-50 bg-background-light/80 dark:bg-background-dark/80 backdrop-blur-md border-b border-slate-200 dark:border-slate-800">
        <div className="flex items-center p-4 justify-between">
          <button
            onClick={() => navigate(-1)}
            className="size-10 flex items-center justify-center rounded-full hover:bg-slate-200 dark:hover:bg-slate-800 transition-colors"
          >
            <span className="material-symbols-outlined">arrow_back</span>
          </button>
          <h2 className="text-lg font-bold text-slate-900 dark:text-slate-100">Search</h2>
          <div className="w-10"></div>
        </div>

        <div className="px-4 pb-3">
          <form onSubmit={handleSearch}>
            <label className="flex w-full">
              <div className="flex w-full items-stretch rounded-xl h-12 bg-slate-200/50 dark:bg-slate-800/50 border border-transparent focus-within:border-primary focus-within:ring-1 focus-within:ring-primary transition-all">
                <div className="text-slate-500 dark:text-slate-400 flex items-center justify-center pl-4">
                  <span className="material-symbols-outlined">search</span>
                </div>
                <input
                  type="text"
                  value={localQuery}
                  onChange={(e) => setLocalQuery(e.target.value)}
                  className="w-full bg-transparent border-none focus:ring-0 text-slate-900 dark:text-slate-100 placeholder:text-slate-500 dark:placeholder:text-slate-400 px-3 text-base outline-none"
                  placeholder="Search receipts, brands, or items"
                />
              </div>
            </label>
          </form>
        </div>
      </div>

      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-bold text-slate-900 dark:text-slate-100">
          {query ? `Results for "${query}"` : 'Search to get started'}
        </h3>
        {query && (
          <button
            onClick={() => navigate('/search')}
            className="text-xs font-medium text-primary"
          >
            Clear
          </button>
        )}
      </div>

        {loading ? (
          <LoadingSpinner />
        ) : invoices.length === 0 ? (
          <Card className="p-8 text-center">
            <span className="material-symbols-outlined text-4xl text-slate-300 mb-2">search</span>
            <p className="text-slate-500 dark:text-slate-400">
              {query ? 'No results found' : 'Search for your warranties and receipts'}
            </p>
          </Card>
        ) : (
          <div className="space-y-3">
            {invoices.map((invoice) => (
              <Card
                key={invoice.id}
                className="p-4 flex items-start gap-4 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors"
                onClick={() => navigate(`/invoice/${invoice.id}`)}
              >
                <div className="flex-1 min-w-0">
                  <div className="flex justify-between items-start">
                    <h4 className="font-bold text-slate-900 dark:text-slate-100 truncate">
                      {invoice.product_name}
                    </h4>
                    <Badge status={invoice.warranty_status} />
                  </div>
                  <p className="text-sm text-slate-500 dark:text-slate-400">
                    {invoice.brand} • {invoice.formatted_amount}
                  </p>
                  <div className="flex items-center text-xs text-slate-400 mt-1">
                    <span className="material-symbols-outlined text-xs mr-1">history</span>
                    Expires in {invoice.days_remaining} days
                  </div>
                </div>
              </Card>
            ))}
          </div>
        )}
    </Layout>
  );
}
