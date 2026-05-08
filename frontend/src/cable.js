import { createConsumer } from '@rails/actioncable';

// Get JWT token from localStorage
const getToken = () => {
  return localStorage.getItem('authToken');
};

// Create ActionCable consumer with authentication
const cable = createConsumer(`${import.meta.env.VITE_API_URL || 'http://localhost:3005'}/cable?token=${getToken()}`);

export default cable;
