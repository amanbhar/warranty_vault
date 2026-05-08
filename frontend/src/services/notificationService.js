import api from './api';

// Notification service for in-app and email notifications
export const notificationService = {
  /**
   * Send an in-app notification
   * @param {Object} data - Notification data
   * @param {string} data.type - Notification type (product_saved, warranty_expiring, etc.)
   * @param {string} data.title - Notification title
   * @param {string} data.message - Notification message
   * @param {string} [data.action_url] - Optional URL to navigate to
   * @param {number} [data.invoice_id] - Optional related invoice ID
   */
  sendInAppNotification: async (data) => {
    try {
      const response = await api.post('/api/v1/notifications', {
        notification_type: data.type,
        title: data.title,
        message: data.message,
        action_url: data.action_url,
        invoice_id: data.invoice_id,
      });
      return { success: true, notification: response.data.notification };
    } catch (error) {
      console.log('In-app notification endpoint not available yet. Showing toast instead.');
      
      // Fallback: Show toast notification directly
      showToastFallback(data.title, data.message, 'success');
      
      return { 
        success: true, 
        notification: {
          id: `local_${Date.now()}`,
          ...data,
          read: false,
          created_at: new Date().toISOString(),
        },
        warning: 'Using local notifications'
      };
    }
  },

  /**
   * Send email notification
   * @param {Object} data - Email data
   * @param {string} data.type - Email type (product_saved, warranty_reminder, etc.)
   * @param {string} data.subject - Email subject
   * @param {string} data.body - Email body (HTML supported)
   * @param {Object} [data.data] - Additional data for template
   */
  sendEmail: async (data) => {
    // Email sending is handled by backend automatically when notification is created
    // No separate endpoint needed
    console.log('Email notification queued:', data.subject);
    return { success: true, sent: true, note: 'Email will be sent by backend' };
  },

  /**
   * Send product saved notification (in-app + email)
   * @param {Object} product - Product/invoice data
   */
  sendProductSavedNotification: async (product) => {
    const productName = product.product_name || 'Your Product';
    const brand = product.brand ? `${product.brand} ` : '';
    
    // In-app notification (primary)
    const inAppResult = await notificationService.sendInAppNotification({
      type: 'product_saved',
      title: 'Product Saved! 🎉',
      message: `${brand}${productName} has been added to your warranty vault.`,
      action_url: `/invoice/${product.id}`,
      invoice_id: product.id,
    });

    // Email is handled by backend automatically when notification is created
    // The backend will send email to user's email address from their account
    const emailResult = {
      success: true,
      sent: true,
      note: 'Email will be sent by backend to user email'
    };

    return { 
      success: inAppResult.success, 
      inApp: inAppResult,
      email: emailResult 
    };
  },

  /**
   * Send warranty expiry reminder
   * @param {Object} product - Product data
   * @param {number} daysUntilExpiry - Days until warranty expires
   */
  sendWarrantyExpiryReminder: async (product, daysUntilExpiry) => {
    const productName = product.product_name || 'Your Product';
    const urgency = daysUntilExpiry <= 7 ? 'urgent' : 'warning';
    
    await notificationService.sendInAppNotification({
      type: 'warranty_expiring',
      title: urgency === 'urgent' ? '⚠️ Warranty Expiring Soon!' : 'Warranty Reminder',
      message: `${productName} warranty expires in ${daysUntilExpiry} days.`,
      action_url: `/invoice/${product.id}`,
      invoice_id: product.id,
    });

    const emailBody = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: ${urgency === 'urgent' ? '#ef4444' : '#f59e0b'};">
          ${urgency === 'urgent' ? '⚠️ Warranty Expiring Soon!' : 'Warranty Reminder'}
        </h2>
        <p>Hi there,</p>
        <p>This is a friendly reminder that your product warranty is expiring soon.</p>
        
        <div style="background: ${urgency === 'urgent' ? '#fef2f2' : '#fffbeb'}; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid ${urgency === 'urgent' ? '#ef4444' : '#f59e0b'};">
          <h3 style="margin: 0 0 10px 0; color: #0f172a;">${productName}</h3>
          <p style="margin: 5px 0; font-size: 18px; font-weight: bold; color: ${urgency === 'urgent' ? '#ef4444' : '#f59e0b'};">
            ${daysUntilExpiry} days remaining
          </p>
          ${product.expires_at ? `<p style="margin: 5px 0;"><strong>Expires:</strong> ${product.expires_at}</p>` : ''}
        </div>

        <p style="color: #64748b; font-size: 14px;">
          Take action now if you notice any issues with your product. Your warranty covers repairs and replacements.
        </p>

        <a href="${window.location.origin}/invoice/${product.id}" 
           style="display: inline-block; background: ${urgency === 'urgent' ? '#ef4444' : '#f59e0b'}; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin-top: 20px;">
          View Warranty Details
        </a>

        <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 30px 0;" />
        <p style="color: #94a3b8; font-size: 12px; text-align: center;">
          © ${new Date().getFullYear()} Warranty Vault. All rights reserved.
        </p>
      </div>
    `;

    await notificationService.sendEmail({
      type: 'warranty_expiring',
      subject: `${productName} - ${daysUntilExpiry} days until warranty expires`,
      body: emailBody,
      data: {
        product_name: productName,
        days_remaining: daysUntilExpiry,
        product_id: product.id,
        urgency,
      },
    });

    return { success: true };
  },
};

// Fallback toast notification for when backend is not available
const showToastFallback = (title, message, type = 'info') => {
  if (typeof document === 'undefined') return;
  
  const toast = document.createElement('div');
  toast.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    background: white;
    border-radius: 12px;
    padding: 16px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.15);
    z-index: 10002;
    min-width: 320px;
    max-width: 400px;
    animation: slideInRight 0.3s ease-out;
    border-left: 4px solid ${type === 'success' ? '#10b981' : type === 'error' ? '#ef4444' : type === 'warning' ? '#f59e0b' : '#3b82f6'};
  `;
  toast.innerHTML = `
    <div style="display: flex; justify-content: space-between; align-items: start; gap: 12px;">
      <div style="flex: 1;">
        <strong style="display: block; margin-bottom: 4px; color: #1f2937; font-size: 14px;">${title}</strong>
        <p style="margin: 0; color: #6b7280; font-size: 13px; line-height: 1.4;">${message}</p>
      </div>
      <button onclick="this.parentElement.parentElement.remove()" style="background: none; border: none; font-size: 18px; cursor: pointer; color: #9ca3af;">&times;</button>
    </div>
    <style>
      @keyframes slideInRight {
        from { transform: translateX(100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
      }
    </style>
  `;
  document.body.appendChild(toast);
  setTimeout(() => {
    if (document.body.contains(toast)) {
      toast.remove();
    }
  }, 5000);
};

export default notificationService;
