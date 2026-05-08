import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  // Use environment variable or default to localhost
  const apiTarget = process.env.VITE_API_URL || env.VITE_API_URL || 'http://localhost:3005';
  console.log(apiTarget);
  return {
    plugins: [react()],
    server: {
      port: 3006,
      host: true, // Needed for Docker to expose the port
      proxy: {
        '/api': {
          target: apiTarget,
          changeOrigin: true
        },
        // Google OAuth callback - must proxy to backend
        '/auth/google': {
          target: apiTarget,
          changeOrigin: true
        },
        '/auth/google_oauth2': {
          target: apiTarget,
          changeOrigin: true
        },
        '/auth/google/callback': {
          target: apiTarget,
          changeOrigin: true
        },
        '/auth/google_oauth2/callback': {
          target: apiTarget,
          changeOrigin: true
        },
        '/ws': {
          target: apiTarget,
          ws: true
        }
      }
    }
  }
})
