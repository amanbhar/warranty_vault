import { cn } from '../utils/cn';

export function Card({ className, children, ...props }) {
  return (
    <div 
      className={cn(
        'bg-white dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-800 shadow-sm',
        className
      )} 
      {...props}
    >
      {children}
    </div>
  );
}

export function CardHeader({ className, children, ...props }) {
  return (
    <div className={cn('px-4 py-3 border-b border-slate-100 dark:border-slate-800', className)} {...props}>
      {children}
    </div>
  );
}

export function CardContent({ className, children, ...props }) {
  return (
    <div className={cn('p-4', className)} {...props}>
      {children}
    </div>
  );
}

export function CardFooter({ className, children, ...props }) {
  return (
    <div className={cn('px-4 py-3 border-t border-slate-100 dark:border-slate-800', className)} {...props}>
      {children}
    </div>
  );
}
