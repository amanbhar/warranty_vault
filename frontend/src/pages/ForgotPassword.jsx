import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { authAPI } from '../services/api';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function ForgotPassword() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [submitted, setSubmitted] = useState(false);

  const { register, handleSubmit, formState: { errors } } = useForm();

  const onSubmit = async (data) => {
    setLoading(true);
    setSubmitError('');
    setSubmitted(false);

    try {
      await authAPI.forgotPassword(data.email);
      setSubmitted(true);
      // Redirect to login after 2 seconds (loading stays on until redirect)
      setTimeout(() => {
        navigate('/login');
      }, 2000);
    } catch (error) {
      setSubmitError(error.response?.data?.error || 'Failed to request password reset');
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-background-light dark:bg-background-dark flex flex-col items-center justify-center p-4">
      <div className="w-full max-w-md bg-white dark:bg-slate-900/50 rounded-xl p-6 shadow-sm border border-slate-200 dark:border-slate-800">
        <h1 className="text-2xl font-bold text-slate-900 dark:text-slate-100 mb-2">Forgot Password</h1>
        <p className="text-slate-600 dark:text-slate-400 mb-6">Enter your email to receive a password reset link.</p>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {submitError && <div className="bg-red-50 text-red-600 p-3 rounded-lg text-sm">{submitError}</div>}
          {submitted && <div className="bg-green-50 text-green-700 p-3 rounded-lg text-sm">If an account exists for this email, a reset link has been sent.</div>}

          <Input
            id="forgot-email"
            type="email"
            autoComplete="email"
            placeholder="Email"
            error={errors.email?.message}
            {...register('email', { required: 'Email is required' })}
          />

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? <LoadingSpinner /> : 'Send Reset Link'}
          </Button>
        </form>

        <p className="text-center text-sm text-slate-500 dark:text-slate-400 mt-4">
          <Link to="/login" className="text-primary font-medium hover:underline">Back to Login</Link>
        </p>
      </div>
    </div>
  );
}
