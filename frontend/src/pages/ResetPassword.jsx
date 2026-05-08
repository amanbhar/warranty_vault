import { useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { authAPI } from '../services/api';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function ResetPassword() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') || '';

  const [loading, setLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [success, setSuccess] = useState(false);

  const { register, handleSubmit, watch, formState: { errors } } = useForm();
  const password = watch('password');

  const onSubmit = async (data) => {
    if (!token) {
      setSubmitError('Invalid or missing reset token');
      return;
    }

    setLoading(true);
    setSubmitError('');

    try {
      await authAPI.resetPassword({
        token,
        password: data.password,
        password_confirmation: data.confirm_password,
      });
      setSuccess(true);
      setTimeout(() => navigate('/login'), 1500);
    } catch (error) {
      setSubmitError(error.response?.data?.error || 'Failed to reset password');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-background-light dark:bg-background-dark flex flex-col items-center justify-center p-4">
      <div className="w-full max-w-md bg-white dark:bg-slate-900/50 rounded-xl p-6 shadow-sm border border-slate-200 dark:border-slate-800">
        <h1 className="text-2xl font-bold text-slate-900 dark:text-slate-100 mb-2">Reset Password</h1>
        <p className="text-slate-600 dark:text-slate-400 mb-6">Enter a new password for your account.</p>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {submitError && <div className="bg-red-50 text-red-600 p-3 rounded-lg text-sm">{submitError}</div>}
          {success && <div className="bg-green-50 text-green-700 p-3 rounded-lg text-sm">Password reset successful. Redirecting to login.</div>}

          <Input
            id="reset-password"
            type="password"
            autoComplete="new-password"
            placeholder="New password"
            error={errors.password?.message}
            {...register('password', {
              required: 'Password is required',
              minLength: { value: 8, message: 'Password must be at least 8 characters' }
            })}
          />

          <Input
            id="reset-confirm-password"
            type="password"
            autoComplete="new-password"
            placeholder="Confirm new password"
            error={errors.confirm_password?.message}
            {...register('confirm_password', {
              required: 'Please confirm your password',
              validate: (value) => value === password || 'Passwords do not match'
            })}
          />

          <Button type="submit" className="w-full" disabled={loading || success}>
            {loading ? <LoadingSpinner /> : 'Reset Password'}
          </Button>
        </form>

        <p className="text-center text-sm text-slate-500 dark:text-slate-400 mt-4">
          <Link to="/login" className="text-primary font-medium hover:underline">Back to Login</Link>
        </p>
      </div>
    </div>
  );
}
