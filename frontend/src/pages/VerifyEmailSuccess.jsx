import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import useAuthStore from '../store/authStore';
import { authAPI } from '../services/api';
import { Button } from '../components/Button';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function VerifyEmailSuccess() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { login } = useAuthStore();
  const [isVerifying, setIsVerifying] = useState(false);
  const [verificationResult, setVerificationResult] = useState(null);
  const [error, setError] = useState('');

  const token = searchParams.get('token');
  const verified = searchParams.get('verified') === 'true';
  const errorMessage = searchParams.get('error');

  useEffect(() => {
    if (errorMessage) {
      const decodedError = decodeURIComponent(errorMessage);
      setError(decodedError);
      setVerificationResult({ success: false, message: decodedError });
      return;
    }

    if (!token) {
      setError('Invalid verification link');
      setVerificationResult({ success: false, message: 'Invalid verification link' });
      return;
    }

    if (verified) {
      loginWithJwt(token);
    } else {
      verifyAndLogin(token);
    }
  }, [token, verified, errorMessage]);

  const loginWithJwt = async (jwtToken) => {
    setIsVerifying(true);
    setError('');

    try {
      localStorage.setItem('authToken', jwtToken);
      const meResponse = await authAPI.me();
      const user = meResponse.data?.user;
      if (!user) throw new Error('Missing user');

      await login({ token: jwtToken, user });
      setVerificationResult({
        success: true,
        message: 'Your email has been verified and you are now logged in.'
      });
      setTimeout(() => {
        navigate('/dashboard', { replace: true });
      }, 1500);
    } catch (err) {
      localStorage.removeItem('authToken');
      const message = err.response?.data?.error || 'Verification failed. Please try logging in manually.';
      setError(message);
      setVerificationResult({ success: false, message });
    } finally {
      setIsVerifying(false);
    }
  };

  const verifyAndLogin = async (verificationToken) => {
    setIsVerifying(true);
    setError('');

    try {
      const response = await authAPI.verifyEmail(verificationToken);
      const { token: jwtToken, user } = response.data;

      if (!jwtToken || !user) {
        throw new Error('Missing auth payload after verification');
      }

      await login({ token: jwtToken, user });

      setVerificationResult({
        success: true,
        message: 'Your email has been verified and you are now logged in.'
      });

      setTimeout(() => {
        navigate('/dashboard', { replace: true });
      }, 1500);
    } catch (err) {
      const message = err.response?.data?.error || 'Verification failed. Please try logging in manually.';
      setError(message);
      setVerificationResult({ success: false, message });
    } finally {
      setIsVerifying(false);
    }
  };

  return (
    <div className="min-h-screen bg-background-light dark:bg-background-dark flex flex-col items-center justify-center p-4">
      <div className="w-full max-w-md flex flex-col items-center text-center mb-8">
        <div className={`p-3 rounded-xl mb-6 ${verificationResult?.success ? 'bg-green-100' : error ? 'bg-red-100' : 'bg-blue-100'}`}>
          <span className={`material-symbols-outlined text-4xl ${verificationResult?.success ? 'text-green-600' : error ? 'text-red-600' : 'text-blue-600'}`}>
            {verificationResult?.success ? 'check_circle' : error ? 'error' : 'email'}
          </span>
        </div>
        <h1 className="text-3xl font-bold text-slate-900 dark:text-slate-100 mb-2">
          {isVerifying ? 'Verifying...' : verificationResult?.success ? 'Email Verified!' : 'Verification Failed'}
        </h1>
        <p className="text-slate-600 dark:text-slate-400">
          {isVerifying ? 'Please wait while we verify your email.' : verificationResult?.message}
        </p>
      </div>

      <div className="w-full max-w-md bg-white dark:bg-slate-900/50 rounded-xl p-6 shadow-sm border border-slate-200 dark:border-slate-800">
        {isVerifying ? (
          <div className="text-center py-8">
            <LoadingSpinner size="lg" />
          </div>
        ) : verificationResult?.success ? (
          <Button onClick={() => navigate('/dashboard', { replace: true })} className="w-full">
            Go to Dashboard
          </Button>
        ) : (
          <div className="space-y-3">
            <Button onClick={() => navigate('/verify-email')} variant="outline" className="w-full">
              Request New Verification Email
            </Button>
            <Button onClick={() => navigate('/login')} variant="ghost" className="w-full">
              Back to Login
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}
