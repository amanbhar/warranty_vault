import { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import useAuthStore from '../store/authStore';
import { authAPI } from '../services/api';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function Login() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { loginWithCredentials, error: storeError, clearError } = useAuthStore();
  const verificationMessage = searchParams.get('message') === 'verify_email'
    ? 'Verify your email before logging in. We sent you a verification link.'
    : '';
  const [submitError, setSubmitError] = useState(searchParams.get('error') ? 'Google authentication failed' : '');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isResending, setIsResending] = useState(false);
  const [verificationSent, setVerificationSent] = useState(false);

  const { register, handleSubmit, formState: { errors }, watch } = useForm();

  const watchedEmail = watch('email');

  const onSubmit = async (data) => {
    clearError();
    setSubmitError('');
    setIsSubmitting(true);
    setVerificationSent(false);

    const result = await loginWithCredentials(data);

    setIsSubmitting(false);

    if (result.success) {
      navigate('/dashboard');
    } else {
      setSubmitError(result.error || 'Login failed');
      // If the error is about email verification, show the resend option
      if (result.error?.includes('verify your email') || result.error?.includes('Email not verified')) {
        setSubmitError(result.error);
      }
    }
  };

  const handleResendVerification = async () => {
    if (!watchedEmail) {
      setSubmitError('Please enter your email address first');
      return;
    }

    setIsResending(true);
    setSubmitError('');

    try {
      const response = await authAPI.resendVerification(watchedEmail);

      if (response.data.success) {
        setVerificationSent(true);
        setSubmitError('');
      } else {
        setSubmitError(response.data.error || 'Failed to resend verification email');
      }
    } catch (error) {
      setSubmitError(error.response?.data?.error || 'Failed to resend verification email');
    } finally {
      setIsResending(false);
    }
  };

  const handleGoogleLogin = () => {
    window.location.href = authAPI.googleUrl({ purpose: 'login' });
  };

  return (
    <div className="min-h-screen bg-background-light dark:bg-background-dark flex flex-col items-center justify-center p-4">
      {/* Header */}
      <div className="w-full max-w-md flex flex-col items-center text-center mb-8">
        <div className="bg-primary/10 p-3 rounded-xl mb-6">
          <span className="material-symbols-outlined text-primary text-4xl">verified_user</span>
        </div>
        <h1 className="text-3xl font-bold text-slate-900 dark:text-slate-100 mb-2">
          Warranty Vault
        </h1>
        <p className="text-slate-600 dark:text-slate-400">
          Securely store and manage your receipts and warranties in one place.
        </p>
      </div>

      {/* Auth Card */}
      <div className="w-full max-w-md bg-white dark:bg-slate-900/50 rounded-xl p-6 shadow-sm border border-slate-200 dark:border-slate-800">
        <div className="space-y-4">
          {verificationMessage && (
            <div className="bg-blue-50 dark:bg-blue-900/20 text-blue-600 dark:text-blue-400 p-3 rounded-lg text-sm">
              {verificationMessage}
            </div>
          )}

          {/* Google Sign In */}
          <button
            onClick={handleGoogleLogin}
            className="w-full flex items-center justify-center gap-3 bg-white border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors py-3 px-4 rounded-lg font-medium text-slate-700 dark:text-slate-200"
          >
            <svg className="w-5 h-5" viewBox="0 0 24 24">
              <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4" />
              <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
              <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.26.81-.58z" fill="#FBBC05" />
              <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
            </svg>
            Continue with Google
          </button>

          {/* Divider */}
          <div className="flex items-center gap-4 py-2">
            <div className="h-px flex-1 bg-slate-200 dark:bg-slate-800"></div>
            <span className="text-xs uppercase tracking-wider text-slate-400 font-semibold">or</span>
            <div className="h-px flex-1 bg-slate-200 dark:bg-slate-800"></div>
          </div>

          {/* Login Form */}
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            {submitError && (
              <div className={`p-3 rounded-lg text-sm ${submitError.includes('verify your email') || submitError.includes('Email not verified')
                  ? 'bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400'
                  : 'bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400'
                }`}>
                <div className="flex items-start gap-2">
                  <span className="material-symbols-outlined text-lg mt-0.5">
                    {submitError.includes('verify your email') || submitError.includes('Email not verified')
                      ? 'warning'
                      : 'error'
                    }
                  </span>
                  <div>
                    <p>{submitError}</p>
                    {(submitError.includes('verify your email') || submitError.includes('Email not verified')) && (
                      <p className="text-xs mt-1 opacity-90">
                        Enter your email below and click "Resend Verification Email"
                      </p>
                    )}
                  </div>
                </div>
              </div>
            )}

            {verificationSent && (
              <div className="bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 p-3 rounded-lg text-sm">
                <div className="flex items-start gap-2">
                  <span className="material-symbols-outlined text-lg mt-0.5">check_circle</span>
                  <div>
                    <p>Verification email sent! Please check your inbox.</p>
                    <p className="text-xs mt-1 opacity-90">
                      Don't forget to check your spam folder.
                    </p>
                  </div>
                </div>
              </div>
            )}

            <Input
              id="login-email"
              type="email"
              autoComplete="username"
              placeholder="Email"
              error={errors.email?.message}
              {...register('email', {
                required: 'Email is required',
                pattern: {
                  value: /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i,
                  message: 'Invalid email address'
                }
              })}
            />

            <Input
              id="login-password"
              type="password"
              autoComplete="current-password"
              placeholder="Password"
              error={errors.password?.message}
              {...register('password', {
                required: 'Password is required',
                minLength: {
                  value: 6,
                  message: 'Password must be at least 6 characters'
                }
              })}
            />

            {/* Resend Verification Button */}
            {(submitError.includes('verify your email') || submitError.includes('Email not verified')) && watchedEmail && (
              <div className="flex flex-col gap-2">
                <Button
                  type="button"
                  onClick={handleResendVerification}
                  disabled={isResending}
                  variant="outline"
                  className="w-full"
                >
                  {isResending ? (
                    <>
                      <LoadingSpinner size="sm" />
                      Sending...
                    </>
                  ) : (
                    <>
                      <span className="material-symbols-outlined text-lg">email</span>
                      Resend Verification Email
                    </>
                  )}
                </Button>
              </div>
            )}

            <Button type="submit" className="w-full" disabled={isSubmitting}>
              {isSubmitting ? <LoadingSpinner /> : 'Log in'}
            </Button>

            <button
              type="button"
              onClick={() => navigate('/forgot-password')}
              className="w-full text-sm text-primary hover:underline"
            >
              Forgot password?
            </button>
          </form>

        </div>
      </div>

      {/* Privacy reassurance */}
      <div className="w-full max-w-md mt-8 flex flex-col items-center">
        <div className="flex items-center gap-2 text-slate-500 dark:text-slate-400 text-sm">
          <span className="material-symbols-outlined text-lg">lock</span>
          <span>Secure authentication with encrypted data storage</span>
        </div>
      </div>
    </div>
  );
}
