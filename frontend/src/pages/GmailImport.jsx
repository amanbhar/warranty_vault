import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { gmailAPI } from '../services/api';
import { Header } from '../components/Header';
import { Layout } from '../components/Layout';
import { Card } from '../components/Card';
import { Button } from '../components/Button';
import { LoadingSpinner } from '../components/LoadingSpinner';

export function GmailImport() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [connection, setConnection] = useState(null);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [message, setMessage] = useState(searchParams.get('connected') ? 'Gmail connected successfully. Sync has started.' : '');
  const [error, setError] = useState(searchParams.get('error') ? 'Unable to connect Gmail.' : '');
  
  useEffect(() => {
    fetchConnection();
  }, []);
  
  const fetchConnection = async () => {
    try {
      const response = await gmailAPI.getConnection();
      setConnection(response.data.connection);
    } catch (error) {
      console.error('Failed to fetch connection:', error);
    } finally {
      setLoading(false);
    }
  };
  
  const handleConnect = () => {
    setError('');
    gmailAPI.connect()
      .then((response) => {
        window.location.href = response.data.oauth_url;
      })
      .catch(() => {
        setError('Failed to start Gmail connection.');
      });
  };
  
  const handleSync = async () => {
    setSyncing(true);
    try {
      await gmailAPI.sync();
      // Poll for completion or show success message
      setTimeout(() => {
        setSyncing(false);
        alert('Sync started! You\'ll be notified when complete.');
      }, 2000);
    } catch (error) {
      setSyncing(false);
      alert('Sync failed. Please try again.');
    }
  };
  
  const handleDisconnect = async () => {
    if (confirm('Are you sure you want to disconnect Gmail?')) {
      try {
        await gmailAPI.disconnect();
        setConnection(null);
      } catch (error) {
        alert('Failed to disconnect');
      }
    }
  };
  
  if (loading) {
    return <LoadingSpinner />;
  }
  
  return (
    <Layout>
      <Header title="Import from Gmail" showBack />

      {message && (
        <div className="mb-4 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {message}
        </div>
      )}

      {error && (
        <div className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

        {!connection?.connected ? (
          /* Connect Gmail */
          <Card className="overflow-hidden">
            <div className="w-full bg-primary/10 flex items-center justify-center py-8">
              <div className="relative">
                <div className="bg-white dark:bg-slate-900 p-4 rounded-2xl shadow-lg border border-primary/20">
                  <span className="material-symbols-outlined text-primary text-5xl">shield_person</span>
                </div>
                <div className="absolute -bottom-2 -right-2 bg-green-500 text-white p-1 rounded-full border-2 border-white dark:border-slate-800">
                  <span className="material-symbols-outlined text-xs">check</span>
                </div>
              </div>
            </div>
            
            <div className="p-6">
              <p className="text-lg font-bold text-slate-900 dark:text-slate-100 mb-2">
                Privacy First Connection
              </p>
              <p className="text-slate-500 dark:text-slate-400 text-sm mb-4">
                We use restricted read-only access to identify digital receipts and warranty confirmations. Your personal correspondence is never accessed, stored, or shared.
              </p>
              
              <Button 
                onClick={handleConnect}
                className="w-full mt-4"
              >
                <span className="material-symbols-outlined mr-2">sync</span>
                Connect Gmail
              </Button>
            </div>
          </Card>
        ) : (
          /* Connected State */
          <>
            <Card className="p-4 mb-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="size-10 bg-red-50 dark:bg-red-900/20 rounded-lg flex items-center justify-center">
                    <span className="material-symbols-outlined text-red-600">mail</span>
                  </div>
                  <div>
                    <p className="font-medium text-slate-900 dark:text-slate-100">Gmail Connected</p>
                    <p className="text-sm text-slate-500">{connection.email}</p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-xs font-medium text-emerald-600">Active</span>
                  <span className="size-2.5 rounded-full bg-emerald-500"></span>
                </div>
              </div>
              
              <div className="mt-4 flex gap-3">
                <Button 
                  onClick={handleSync}
                  className="flex-1"
                  disabled={syncing}
                >
                  {syncing ? <LoadingSpinner /> : (
                    <>
                      <span className="material-symbols-outlined mr-2">sync</span>
                      Sync Now
                    </>
                  )}
                </Button>
                <Button 
                  onClick={handleDisconnect}
                  variant="outline"
                >
                  Disconnect
                </Button>
              </div>
            </Card>
            
            {/* Suggested Imports Placeholder */}
            <div>
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-xl font-bold text-slate-900 dark:text-slate-100">
                  Recent Imports
                </h2>
              </div>
              
              <Card className="p-8 text-center">
                <span className="material-symbols-outlined text-4xl text-slate-300 mb-2">download</span>
                <p className="text-slate-500 dark:text-slate-400">
                  {syncing ? 'Syncing...' : 'Click "Sync Now" to import receipts from Gmail'}
                </p>
              </Card>
            </div>
          </>
        )}
    </Layout>
  );
}
