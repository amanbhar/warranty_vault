import { BottomNav, DesktopSidebar } from './BottomNav';

export function Layout({ children, className = '' }) {
  return (
    <div className="min-h-screen bg-[#f6f8fb] dark:bg-[#0c1117] pb-28 lg:pb-8">
      <DesktopSidebar />
      
      <div className="lg:ml-64">
        <BottomNav />
        <main className={`max-w-lg mx-auto px-4 pt-4 lg:max-w-6xl lg:px-8 ${className}`}>
          {children}
        </main>
      </div>
    </div>
  );
}
