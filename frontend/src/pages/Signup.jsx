import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import useAuthStore from '../store/authStore';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function Signup() {
  const navigate = useNavigate();
  const { signup, loading, error, clearError } = useAuthStore();
  const [submitError, setSubmitError] = useState('');

  const { register, handleSubmit, watch, formState: { errors } } = useForm();
  const password = watch('password');

  const onSubmit = async (data) => {
    clearError();
    setSubmitError('');

    const result = await signup({
      email: data.email,
      password: data.password,
      first_name: data.first_name,
      last_name: data.last_name,
    });

    if (result.success) {
      navigate('/login?message=verify_email');
    } else {
      setSubmitError(result.error || 'Signup failed');
    }
  };

  return (
    <div className="min-h-screen bg-background-light dark:bg-background-dark flex flex-col items-center justify-center p-4">
      {/* Header */}
      <div className="w-full max-w-md flex flex-col items-center text-center mb-6">
        <div className="bg-primary/10 p-3 rounded-xl mb-4">
          <span className="material-symbols-outlined text-primary text-4xl">verified_user</span>
        </div>
        <h1 className="text-2xl font-bold text-slate-900 dark:text-slate-100 mb-2">
          Create Account
        </h1>
        <p className="text-slate-600 dark:text-slate-400">
          Start tracking your warranties today
        </p>
      </div>

      {/* Signup Card */}
      <div className="w-full max-w-md bg-white dark:bg-slate-900/50 rounded-xl p-6 shadow-sm border border-slate-200 dark:border-slate-800">
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {submitError && (
            <div className="bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 p-3 rounded-lg text-sm">
              {submitError}
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <Input
              id="signup-first-name"
              autoComplete="given-name"
              placeholder="First name"
              error={errors.first_name?.message}
              {...register('first_name')}
            />

            <Input
              id="signup-last-name"
              autoComplete="family-name"
              placeholder="Last name"
              error={errors.last_name?.message}
              {...register('last_name')}
            />
          </div>

          <Input
            id="signup-email"
            type="email"
            autoComplete="email"
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
            id="signup-password"
            type="password"
            autoComplete="new-password"
            placeholder="Password"
            error={errors.password?.message}
            {...register('password', {
              required: 'Password is required',
              minLength: {
                value: 8,
                message: 'Password must be at least 8 characters'
              }
            })}
          />

          <Input
            id="signup-confirm-password"
            type="password"
            autoComplete="new-password"
            placeholder="Confirm password"
            error={errors.confirm_password?.message}
            {...register('confirm_password', {
              required: 'Please confirm your password',
              validate: value => value === password || 'Passwords do not match'
            })}
          />

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? <LoadingSpinner /> : 'Create Account'}
          </Button>
        </form>

        {/* Login link */}
        <p className="text-center text-sm text-slate-500 dark:text-slate-400 mt-4">
          Already have an account?{' '}
          <Link to="/login" className="text-primary font-medium hover:underline">
            Log in
          </Link>
        </p>
      </div>
    </div>
  );
}
