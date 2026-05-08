import { cn } from '../utils/cn';

export function LoadingSpinner({ size = 'default', className }) {
  const sizes = {
    sm: 'h-4 w-4',
    default: 'h-6 w-6',
    lg: 'h-8 w-8',
  };
  
  return (
    <div className={cn('flex items-center justify-center', className)}>
      <span className={cn('material-symbols-outlined animate-spin text-primary', sizes[size])}>
        progress_activity
      </span>
    </div>
  );
}

export function PageLoader() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-background-light dark:bg-background-dark">
      <div className="text-center">
        <LoadingSpinner size="lg" />
        <p className="mt-4 text-slate-500 dark:text-slate-400">Loading...</p>
      </div>
    </div>
  );
}
