import { useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import useAuthStore from '../store/authStore';
import { PageLoader } from '../components/LoadingSpinner';

export function AuthCallback() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { handleOAuthCallback } = useAuthStore();

  useEffect(() => {
    const error = searchParams.get('error');
    const token = searchParams.get('token');

    if (error) {
      navigate(`/login?error=${encodeURIComponent(error)}`, { replace: true });
      return;
    }

    if (token) {
      handleOAuthCallback(token).then((result) => {
        navigate(result.success ? '/dashboard' : '/login?error=authentication_failed', { replace: true });
      });
    } else {
      navigate('/login?error=authentication_failed', { replace: true });
    }
  }, [handleOAuthCallback, navigate, searchParams]);

  return <PageLoader />;
}
