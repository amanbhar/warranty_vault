import { forwardRef } from 'react';
import { cn } from '../utils/cn';

const Input = forwardRef(
  ({ className, type = 'text', error, leftIcon, rightIcon, ...props }, ref) => {
    return (
      <div className="relative">
        {leftIcon && (
          <div className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">
            {leftIcon}
          </div>
        )}
        
        <input
          type={type}
          ref={ref}
          className={cn(
            'w-full px-4 py-3 bg-primary/5 border rounded-lg',
            'focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all',
            'placeholder:text-slate-400',
            error 
              ? 'border-red-500 focus:ring-red-500' 
              : 'border-primary/20',
            leftIcon && 'pl-10',
            rightIcon && 'pr-10',
            className
          )}
          {...props}
        />
        
        {rightIcon && (
          <div className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
            {rightIcon}
          </div>
        )}
        
        {error && (
          <p className="mt-1 text-sm text-red-500">{error}</p>
        )}
      </div>
    );
  }
);

Input.displayName = 'Input';

export { Input };
