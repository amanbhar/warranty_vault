import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { authAPI } from '../services/api';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function VerifyEmail() {
  const navigate = useNavigate();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [verificationSent, setVerificationSent] = useState(false);
  
  const { register, handleSubmit, formState: { errors }, watch } = useForm();
  
  const watchedEmail = watch('email');
  
  const onSubmit = async (data) => {
    setIsSubmitting(true);
    setSubmitError('');
    setVerificationSent(false);
    
    try {
      const response = await authAPI.resendVerification(data.email);
      
      if (response.data.success) {
        setVerificationSent(true);
        setSubmitError('');
      } else {
        setSubmitError(response.data.error || 'Failed to resend verification email');
      }
    } catch (error) {
      setSubmitError(error.response?.data?.error || 'Failed to resend verification email');
    } finally {
      setIsSubmitting(false);
    }
  };
  
  const handleTokenVerification = (token) => {
    navigate(`/verify-email-success?token=${token}`);
  };
  
  return (
    <div className="min-h-screen bg-background-light dark:bg-background-dark flex flex-col items-center justify-center p-4">
      {/* Header */}
      <div className="w-full max-w-md flex flex-col items-center text-center mb-8">
        <div className="bg-primary/10 p-3 rounded-xl mb-6">
          <span className="material-symbols-outlined text-primary text-4xl">email</span>
        </div>
        <h1 className="text-3xl font-bold text-slate-900 dark:text-slate-100 mb-2">
          Verify Your Email
        </h1>
        <p className="text-slate-600 dark:text-slate-400">
          Enter your email address to receive a verification link
        </p>
      </div>
      
      {/* Verification Card */}
      <div className="w-full max-w-md bg-white dark:bg-slate-900/50 rounded-xl p-6 shadow-sm border border-slate-200 dark:border-slate-800">
        <div className="space-y-4">
          {/* Success Message */}
          {verificationSent && (
            <div className="bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 p-4 rounded-lg">
              <div className="flex items-start gap-3">
                <span className="material-symbols-outlined text-xl mt-0.5">check_circle</span>
                <div>
                  <p className="font-medium">Verification email sent!</p>
                  <p className="text-sm mt-1 opacity-90">
                    Please check your inbox and click the verification link. Don't forget to check your spam folder.
                  </p>
                </div>
              </div>
            </div>
          )}
          
          {/* Error Message */}
          {submitError && (
            <div className="bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 p-3 rounded-lg text-sm">
              <div className="flex items-start gap-2">
                <span className="material-symbols-outlined text-lg mt-0.5">error</span>
                <p>{submitError}</p>
              </div>
            </div>
          )}
          
          {/* Verification Form */}
          {!verificationSent && (
            <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
                  Email Address
                </label>
                <Input
                  type="email"
                  placeholder="Enter your email address"
                  error={errors.email?.message}
                  {...register('email', {
                    required: 'Email is required',
                    pattern: {
                      value: /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i,
                      message: 'Invalid email address'
                    }
                  })}
                />
              </div>
              
              <Button type="submit" className="w-full" disabled={isSubmitting}>
                {isSubmitting ? (
                  <>
                    <LoadingSpinner size="sm" />
                    Sending Verification Email...
                  </>
                ) : (
                  <>
                    <span className="material-symbols-outlined text-lg mr-2">send</span>
                    Send Verification Email
                  </>
                )}
              </Button>
            </form>
          )}
          
          {/* Token Verification Section */}
          {verificationSent && (
            <div className="border-t border-slate-200 dark:border-slate-700 pt-4">
              <p className="text-sm text-slate-600 dark:text-slate-400 text-center mb-3">
                Already have a verification token?
              </p>
              <div className="space-y-3">
                <Input
                  type="text"
                  placeholder="Enter verification token"
                  onChange={(e) => {
                    if (e.target.value.length > 10) {
                      handleTokenVerification(e.target.value);
                    }
                  }}
                />
                <p className="text-xs text-slate-500 dark:text-slate-400 text-center">
                  Paste your token here to verify instantly
                </p>
              </div>
            </div>
          )}
          
          {/* Back to Login */}
          <div className="text-center pt-4 border-t border-slate-200 dark:border-slate-700">
            <button
              onClick={() => navigate('/login')}
              className="text-sm text-primary hover:underline font-medium"
            >
              ← Back to Login
            </button>
          </div>
        </div>
      </div>
      
      {/* Help Section */}
      <div className="w-full max-w-md mt-8 flex flex-col items-center">
        <div className="bg-amber-50 dark:bg-amber-900/20 p-4 rounded-lg border border-amber-200 dark:border-amber-800">
          <div className="flex items-start gap-3">
            <span className="material-symbols-outlined text-amber-600 dark:text-amber-400 text-lg mt-0.5">
              info
            </span>
            <div className="text-sm">
              <p className="font-medium text-amber-800 dark:text-amber-200 mb-1">
                Need Help?
              </p>
              <ul className="text-amber-700 dark:text-amber-300 space-y-1">
                <li>• Check your spam folder</li>
                <li>• Wait a few minutes for delivery</li>
                <li>• Ensure email address is correct</li>
                <li>• Contact support if issues persist</li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
