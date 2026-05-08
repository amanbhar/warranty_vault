import { NavLink } from 'react-router-dom';
import { cn } from '../utils/cn';

export function BottomNav() {
  const navItems = [
    { to: '/dashboard', icon: 'home', label: 'Dashboard' },
    { to: '/timeline', icon: 'history', label: 'Timeline' },
    { to: '/vault', icon: 'inventory_2', label: 'Vault' },
  ];

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-white dark:bg-slate-900 border-t border-slate-200 dark:border-slate-800 px-6 py-2 z-50 lg:hidden">
      <div className="max-w-md mx-auto flex justify-between items-center">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) => cn(
              'flex flex-col items-center gap-1 transition-colors',
              'text-slate-400 dark:text-slate-500 hover:text-primary',
              isActive && 'text-primary'
            )}
          >
            <>
              <span className="material-symbols-outlined">{item.icon}</span>
              <span className="text-[10px] font-medium uppercase tracking-wider">{item.label}</span>
            </>
          </NavLink>
        ))}
      </div>
    </nav>
  );
}

export function DesktopSidebar() {
  const navItems = [
    { to: '/dashboard', icon: 'home', label: 'Dashboard' },
    { to: '/timeline', icon: 'history', label: 'Timeline' },
    { to: '/vault', icon: 'inventory_2', label: 'Vault' },
  ];

  return (
    <aside className="hidden lg:flex lg:flex-col lg:fixed lg:inset-y-0 lg:w-64 bg-white dark:bg-slate-900 border-r border-slate-200 dark:border-slate-800 z-50">
      {/* Logo */}
      <div className="h-16 flex items-center px-6 border-b border-slate-200 dark:border-slate-800">
        <span className="material-symbols-outlined text-primary text-2xl mr-2">verified_user</span>
        <span className="font-display font-bold text-lg text-slate-900 dark:text-slate-100">Warranty Vault</span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 py-4 px-3 space-y-1">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) => cn(
              'flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
              'text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800',
              isActive && 'bg-primary/10 text-primary dark:bg-primary/20'
            )}
          >
            <span className="material-symbols-outlined text-xl">{item.icon}</span>
            {item.label}
          </NavLink>
        ))}
      </nav>

      {/* Footer */}
      <div className="p-4 border-t border-slate-200 dark:border-slate-800">
        <button
          onClick={() => window.location.href = '/upload'}
          className="w-full btn-primary flex items-center justify-center gap-2"
        >
          <span className="material-symbols-outlined text-lg">add_circle</span>
          Quick Upload
        </button>
      </div>
    </aside>
  );
}
