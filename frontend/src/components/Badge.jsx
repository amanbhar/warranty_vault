import { cn } from '../utils/cn';

export function Badge({ status, children }) {
  const variants = {
    active: 'bg-green-100 dark:bg-green-900/30 text-green-600 dark:text-green-400',
    expiring_soon: 'bg-amber-100 dark:bg-amber-900/30 text-amber-600 dark:text-amber-400',
    expired: 'bg-slate-100 dark:bg-slate-700 text-slate-500 dark:text-slate-400',
  };
  
  const labels = {
    active: 'Active',
    expiring_soon: 'Expiring Soon',
    expired: 'Expired',
  };
  
  return (
    <span className={cn(
      'px-2 py-1 text-[10px] font-bold rounded uppercase',
      variants[status] || variants.active
    )}>
      {children || labels[status] || status}
    </span>
  );
}
