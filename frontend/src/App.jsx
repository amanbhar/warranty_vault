import { BrowserRouter, Routes, Route, Navigate, Outlet } from 'react-router-dom';
import { useEffect } from 'react';
import useAuthStore from './store/authStore';
import { PageLoader } from './components/LoadingSpinner';
import { AuthCallback } from './pages/AuthCallback';
import { Onboarding } from './pages/Onboarding';
import { Login } from './pages/Login';
import { Signup } from './pages/Signup';
import { VerifyEmail } from './pages/VerifyEmail';
import { VerifyEmailSuccess } from './pages/VerifyEmailSuccess';
import { ForgotPassword } from './pages/ForgotPassword';
import { ResetPassword } from './pages/ResetPassword';
import { Dashboard } from './pages/Dashboard';
import { Vault } from './pages/Vault';
import { Upload } from './pages/Upload';
import { ProductDetail } from './pages/ProductDetail';
import { Timeline } from './pages/Timeline';
import { Search } from './pages/Search';
import { GmailImport } from './pages/GmailImport';
import { Settings } from './pages/Settings';
import { EditProduct } from './pages/EditProduct';
import { Notifications } from './pages/Notifications';
import InvoiceWorkflow from './components/InvoiceWorkflow';
import ProductDashboard from './components/ProductDashboard';
import ErrorBoundary from './components/ErrorBoundary';

// Protected Route Component
function ProtectedRoute() {
  const { isAuthenticated, initialize, initialized } = useAuthStore();

  useEffect(() => {
    if (!initialized) {
      initialize();
    }
  }, [initialized, initialize]);

  if (!initialized) {
    return <PageLoader />;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <Outlet />;
}

// Public Route Component (redirect if authenticated)
function PublicRoute({ children }) {
  const { isAuthenticated, initialized } = useAuthStore();

  // Don't wait for initialization for public routes
  // Just check if already authenticated
  if (!initialized) {
    // For public routes, just render without waiting
    return children;
  }

  if (isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  return children;
}

function App() {
  const { initialize, initialized } = useAuthStore();

  useEffect(() => {
    if (!initialized) {
      initialize();
    }
  }, [initialized, initialize]);

  return (
    <BrowserRouter>
      <Routes>
        {/* Public Routes */}
        <Route path="/" element={<Navigate to="/onboarding" replace />} />

        <Route path="/onboarding" element={
          <PublicRoute>
            <Onboarding />
          </PublicRoute>
        } />

        <Route path="/login" element={
          <PublicRoute>
            <Login />
          </PublicRoute>
        } />

        <Route path="/oauth-callback" element={<AuthCallback />} />

        <Route path="/signup" element={
          <PublicRoute>
            <Signup />
          </PublicRoute>
        } />

        <Route path="/verify-email" element={
          <PublicRoute>
            <VerifyEmail />
          </PublicRoute>
        } />

        <Route path="/verify-email-success" element={
          <PublicRoute>
            <VerifyEmailSuccess />
          </PublicRoute>
        } />

        <Route path="/forgot-password" element={
          <PublicRoute>
            <ForgotPassword />
          </PublicRoute>
        } />

        <Route path="/reset-password" element={
          <PublicRoute>
            <ResetPassword />
          </PublicRoute>
        } />

        {/* Protected Routes */}
        <Route element={<ProtectedRoute />}>
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/products" element={<ProductDashboard />} />
          <Route path="/workflow" element={<InvoiceWorkflow />} />
          <Route path="/vault" element={<Vault />} />
          <Route path="/upload" element={<Upload />} />
          <Route path="/invoice/:id" element={<ProductDetail />} />
          <Route path="/invoice/:id/edit" element={<EditProduct />} />
          <Route path="/timeline" element={<Timeline />} />
          <Route path="/search" element={<Search />} />
          <Route path="/gmail-import" element={<GmailImport />} />
          <Route path="/settings" element={<Settings />} />
          <Route path="/notifications" element={<Notifications />} />
        </Route>

        {/* Catch all */}
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
