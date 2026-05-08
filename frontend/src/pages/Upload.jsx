import { useState, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import useInvoiceStore from '../store/invoiceStore';
import { Layout } from '../components/Layout';
import { Header } from '../components/Header';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { Card } from '../components/Card';
import { cn } from '../utils/cn';
import { monthsToYearsAndMonths, yearsAndMonthsToMonths } from '../utils/warrantyDurationHelper';

export function Upload() {
  const navigate = useNavigate();
  const { createInvoice, scanInvoice } = useInvoiceStore();

  const [step, setStep] = useState('upload'); // upload, scanning, review, manual
  const [selectedFile, setSelectedFile] = useState(null);
  const [previewUrl, setPreviewUrl] = useState(null);
  const [ocrData, setOcrData] = useState(null);
  const [ocrError, setOcrError] = useState(null);
  const [submitError, setSubmitError] = useState(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isPrefilledFromScan, setIsPrefilledFromScan] = useState(false);
  const [invoiceFileError, setInvoiceFileError] = useState(null);
  const [reviewItems, setReviewItems] = useState([
    {
      id: Date.now(),
      product_name: '',
      brand: '',
      model_number: '',
      category: 'Other',
      price: null,
      warranties: [{ component: 'product', duration_months: 0, warranty_type: '', details: '' }],
    },
  ]);
  const [scanInsights, setScanInsights] = useState({ warnings: [], missingFields: [] });

  const fileInputRef = useRef(null);
  const { register, handleSubmit, setValue } = useForm();
  const MAX_INVOICE_FILE_SIZE_BYTES = 10 * 1024 * 1024;
  const ALLOWED_INVOICE_MIME_TYPES = ['application/pdf', 'image/jpeg', 'image/png'];
  const ALLOWED_INVOICE_EXTENSIONS = ['.pdf', '.jpg', '.jpeg', '.png'];

  const toNumberOrNull = (value) => {
    if (value === undefined || value === null || value === '') return null;
    if (typeof value === 'number') return Number.isFinite(value) ? value : null;
    const normalized = String(value).trim().replace(/,/g, '');
    if (!/^\d+(\.\d+)?$/.test(normalized)) return null;
    const parsed = Number(normalized);
    return Number.isFinite(parsed) ? parsed : null;
  };

  const sanitizePriceInput = (value) => {
    const onlyAllowed = String(value || '').replace(/[^\d.,]/g, '');
    const withoutCommas = onlyAllowed.replace(/,/g, '');
    const parts = withoutCommas.split('.');
    if (parts.length <= 1) return withoutCommas;
    return `${parts[0]}.${parts.slice(1).join('')}`;
  };

  const sanitizeIntegerInput = (value) => String(value || '').replace(/[^\d]/g, '');

  const hasAllowedInvoiceExtension = (filename = '') => (
    ALLOWED_INVOICE_EXTENSIONS.some((extension) => filename.toLowerCase().endsWith(extension))
  );

  const validateInvoiceFile = (file) => {
    if (!file) return null;
    if (file.size > MAX_INVOICE_FILE_SIZE_BYTES) {
      return 'Invoice file must be 10MB or smaller.';
    }

    const isAllowedMime = ALLOWED_INVOICE_MIME_TYPES.includes(file.type);
    const isAllowedExtension = hasAllowedInvoiceExtension(file.name);
    if (!isAllowedMime && !isAllowedExtension) {
      return 'Only PDF, JPG, or PNG files are allowed.';
    }

    return null;
  };

  const normalizeWarrantyCandidates = (rawWarranties) => {
    const source = Array.isArray(rawWarranties) ? rawWarranties : [];
    const parsed = source.flatMap((warranty) => {
      if (typeof warranty === 'string') {
        const compact = warranty.trim();
        if (!compact) return [];
        if (/^\d+\s*\+\s*\d+/.test(compact)) {
          const parts = compact.split('+').map((part) => toNumberOrNull(part.trim())).filter((part) => part !== null);
          return parts.map((duration, index) => ({
            component: index === 0 ? 'product' : 'extended',
            duration_months: duration,
            warranty_type: '',
            details: compact,
          }));
        }
        const months = toNumberOrNull(compact);
        return [{
          component: 'product',
          duration_months: months,
          warranty_type: '',
          details: compact,
        }];
      }

      if (!warranty || typeof warranty !== 'object') return [];
      const component = warranty.component || warranty.component_name || 'product';
      const durationRaw = warranty.duration_months ?? warranty.warranty_months;
      const details = warranty.details || warranty.description || '';
      const warrantyType = warranty.warranty_type || '';

      if (typeof durationRaw === 'string' && /^\d+\s*\+\s*\d+/.test(durationRaw.trim())) {
        const parts = durationRaw.split('+').map((part) => toNumberOrNull(part.trim())).filter((part) => part !== null);
        return parts.map((duration, index) => ({
          component: index === 0 ? component : 'extended',
          duration_months: duration,
          warranty_type: warrantyType,
          details: details || durationRaw,
        }));
      }

      return [{
        component,
        duration_months: toNumberOrNull(durationRaw),
        warranty_type: warrantyType,
        details,
      }];
    });

    return parsed.length > 0
      ? parsed
      : [{ component: 'product', duration_months: 0, warranty_type: '', details: '' }];
  };

  const normalizeItemsForReview = (invoiceData) => {
    const sourceItems = Array.isArray(invoiceData.items) && invoiceData.items.length > 0
      ? invoiceData.items
      : [{
          product_name: invoiceData.product_name,
          brand: invoiceData.brand,
          model_number: invoiceData.model_number || invoiceData.model,
          category: invoiceData.product_category || invoiceData.category,
          price: invoiceData.product_price ?? invoiceData.amount ?? invoiceData.total_amount,
          warranties: invoiceData.warranties,
        }];

    return sourceItems.map((item, index) => ({
      id: Date.now() + index,
      product_name: item.product_name || '',
      brand: item.brand || '',
      model_number: item.model_number || item.model || '',
      category: item.category || item.product_category || invoiceData.product_category || invoiceData.category || 'Other',
      price: toNumberOrNull(item.price ?? item.product_price ?? item.amount),
      warranties: normalizeWarrantyCandidates(item.warranties),
    }));
  };

  const buildExtractedPayload = (globalData) => {
    const missingFields = [];
    if (!globalData.purchase_date?.trim()) missingFields.push('purchase_date');
    if (!globalData.seller_name?.trim()) missingFields.push('seller_name');

    const items = reviewItems.map((item, index) => {
      if (!item.product_name?.trim()) missingFields.push(`item_${index + 1}_product_name`);
      if (!item.brand?.trim()) missingFields.push(`item_${index + 1}_brand`);

      const warranties = (item.warranties || [])
        .filter((warranty) => warranty.component?.trim())
        .map((warranty) => ({
          component: warranty.component.trim(),
          duration_months: toNumberOrNull(warranty.duration_months),
          warranty_type: warranty.warranty_type || null,
          details: warranty.details || null,
        }));

      if (!warranties.some((warranty) => warranty.duration_months)) {
        missingFields.push(`item_${index + 1}_warranty`);
      }

      return {
        product_name: item.product_name?.trim() || null,
        brand: item.brand?.trim() || null,
        model_number: item.model_number?.trim() || null,
        category: item.category || 'Other',
        price: toNumberOrNull(item.price),
        warranties,
      };
    });

    if (!items.some((item) => item.warranties.some((warranty) => warranty.duration_months))) {
      missingFields.push('warranty');
    }

    const warnings = [...(scanInsights.warnings || [])];
    if (missingFields.includes('warranty') && !warnings.some((warning) => warning.toLowerCase().includes('warranty'))) {
      warnings.push('Warranty details were not found clearly in the invoice. Please review or re-upload a clearer invoice.');
    }

    const explicitAmount = toNumberOrNull(globalData.invoice_amount);
    const computedAmount = items.reduce((sum, item) => (
      item.price !== null && item.price !== undefined ? sum + item.price : sum
    ), 0);
    const hasComputedAmount = items.some((item) => item.price !== null && item.price !== undefined);
    const invoiceAmount = explicitAmount ?? (hasComputedAmount ? computedAmount : null);
    const firstItem = items[0] || {};

    return {
      seller_name: globalData.seller_name?.trim() || globalData.seller?.trim() || null,
      platform_name: globalData.platform_name?.trim() || null,
      invoice_number: globalData.invoice_number?.trim() || null,
      purchase_date: globalData.purchase_date || null,
      product_price: invoiceAmount,
      product_category: firstItem.category || null,
      items,
      warranties: firstItem.warranties || [],
      missing_fields: Array.from(new Set(missingFields)),
      warnings: Array.from(new Set(warnings)),
    };
  };

  const handleFileSelect = (e) => {
    const file = e.target.files[0];
    if (file) {
      const validationError = validateInvoiceFile(file);
      if (validationError) {
        setInvoiceFileError(validationError);
        e.target.value = '';
        return;
      }

      setInvoiceFileError(null);
      setSelectedFile(file);
      const url = window.URL.createObjectURL(file);
      setPreviewUrl(url);
    }
  };

  const handleManualInvoiceSelect = (e) => {
    const file = e.target.files[0];
    if (!file) {
      setInvoiceFileError(null);
      return;
    }

    const validationError = validateInvoiceFile(file);
    if (validationError) {
      setInvoiceFileError(validationError);
      e.target.value = '';
      return;
    }

    setInvoiceFileError(null);
    setSelectedFile(file);
  };

  const handleStartOcr = async () => {
    if (!selectedFile) return;

    setStep('scanning');
    const formData = new FormData();
    formData.append('file', selectedFile);

    const result = await scanInvoice(formData);

    if (result.success) {
      const inv = result.data.data || {};

      setOcrData(inv);
      setIsPrefilledFromScan(true);
      setReviewItems(normalizeItemsForReview(inv));
      setScanInsights({
        warnings: inv.warnings || result.warnings || [],
        missingFields: result.missing_fields || inv.missing_fields || [],
      });

      const formValues = {
        seller_name: inv.seller_name || inv.seller,
        seller: inv.seller || inv.seller_name,
        invoice_number: inv.invoice_number,
        platform_name: inv.platform_name,
        purchase_date: inv.purchase_date,
        invoice_amount: inv.amount ?? inv.total_amount ?? inv.product_price,
      };

      Object.entries(formValues).forEach(([key, value]) => {
        if (value !== undefined && value !== null) {
          setValue(key, key === 'purchase_date' && typeof value === 'string' ? value.split('T')[0] : value);
        }
      });

      setOcrError(null);
      setStep('review');
    } else {
      // Extract missing fields from error response
      const missingFields = result.missing_fields || [];

      // Build detailed error message with missing fields
      let errorMessage = result.error || "We couldn't extract data automatically.";

      if (missingFields.length > 0) {
        const fieldNames = missingFields.map(f => f.replace(/_/g, ' ')).join(', ');
        errorMessage = `Scan failed: Missing required fields - ${fieldNames}`;
      }

      setOcrError(errorMessage);
      setIsPrefilledFromScan(false);
      setScanInsights({
        warnings: [],
        missingFields: missingFields,
      });
      setReviewItems([
        {
          id: Date.now(),
          product_name: '',
          brand: '',
          model_number: '',
          category: 'Other',
          price: null,
          warranties: [{ component: 'product', duration_months: 0, warranty_type: '', details: '' }],
        },
      ]);
      setStep('manual');
    }
  };

  const handleFinalSubmit = async (data) => {
    setSubmitError(null);
    setIsSubmitting(true);
    const selectedFileError = validateInvoiceFile(selectedFile);
    if (selectedFileError) {
      setSubmitError(selectedFileError);
      setInvoiceFileError(selectedFileError);
      setIsSubmitting(false);
      return;
    }

    const formData = new FormData();
    const extractedPayload = buildExtractedPayload(data);
    const firstItem = extractedPayload.items?.[0] || {};

    formData.append('invoice[seller]', extractedPayload.seller_name || '');
    formData.append('invoice[invoice_number]', extractedPayload.invoice_number || '');
    formData.append('invoice[purchase_date]', extractedPayload.purchase_date || '');
    if (extractedPayload.product_price !== null) {
      formData.append('invoice[amount]', String(extractedPayload.product_price));
    }
    formData.append('invoice[category]', extractedPayload.product_category || firstItem.category || 'Other');
    formData.append('invoice[extracted_data]', JSON.stringify(extractedPayload));

    if (selectedFile) {
      formData.append('invoice[file]', selectedFile);
    }

    (extractedPayload.items || []).forEach((item, itemIndex) => {
      formData.append(`invoice[items][${itemIndex}][product_name]`, item.product_name || '');
      formData.append(`invoice[items][${itemIndex}][brand]`, item.brand || '');
      formData.append(`invoice[items][${itemIndex}][model_number]`, item.model_number || '');
      formData.append(`invoice[items][${itemIndex}][category]`, item.category || extractedPayload.product_category || 'Other');
      if (item.price !== null && item.price !== undefined) {
        formData.append(`invoice[items][${itemIndex}][product_price]`, String(item.price));
      }

      (item.warranties || []).forEach((warranty, warrantyIndex) => {
        formData.append(`invoice[items][${itemIndex}][warranties][${warrantyIndex}][component]`, warranty.component || 'product');
        if (warranty.duration_months !== null && warranty.duration_months !== undefined) {
          formData.append(`invoice[items][${itemIndex}][warranties][${warrantyIndex}][duration_months]`, String(warranty.duration_months));
        }
        if (warranty.details) {
          formData.append(`invoice[items][${itemIndex}][warranties][${warrantyIndex}][description]`, warranty.details);
        }
      });
    });

    try {
      const result = await createInvoice(formData);

      if (result.success) {
        const count = extractedPayload.items?.length || 1;
        const message = count > 1
          ? `${count} products have been added to your warranty vault.`
          : `${firstItem.product_name || 'Product'} has been added to your warranty vault.`;
        showToast('Product Saved!', message, 'success');
        navigate(`/invoice/${result.invoice.id}`);
      } else {
        setSubmitError(result.error || 'Failed to save product. Please check your entries.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const addReviewItem = () => {
    setReviewItems((current) => [
      ...current,
      {
        id: Date.now() + current.length + 1,
        product_name: '',
        brand: '',
        model_number: '',
        category: 'Other',
        price: null,
        warranties: [{ component: 'product', duration_months: 0, warranty_type: '', details: '' }],
      },
    ]);
  };

  const removeReviewItem = (itemId) => {
    setReviewItems((current) => (current.length > 1 ? current.filter((item) => item.id !== itemId) : current));
  };

  const updateReviewItem = (itemId, field, value) => {
    setReviewItems((current) => current.map((item) => (
      item.id === itemId ? { ...item, [field]: value } : item
    )));
  };

  const addReviewWarranty = (itemId) => {
    setReviewItems((current) => current.map((item) => {
      if (item.id !== itemId) return item;
      return {
        ...item,
        warranties: [...(item.warranties || []), { component: '', duration_months: 0, warranty_type: '', details: '' }],
      };
    }));
  };

  const removeReviewWarranty = (itemId, warrantyIndex) => {
    setReviewItems((current) => current.map((item) => {
      if (item.id !== itemId) return item;
      if ((item.warranties || []).length <= 1) return item;
      return {
        ...item,
        warranties: item.warranties.filter((_, index) => index !== warrantyIndex),
      };
    }));
  };

  const updateReviewWarranty = (itemId, warrantyIndex, field, value) => {
    setReviewItems((current) => current.map((item) => {
      if (item.id !== itemId) return item;
      return {
        ...item,
        warranties: (item.warranties || []).map((warranty, index) => (
          index === warrantyIndex ? { ...warranty, [field]: value } : warranty
        )),
      };
    }));
  };

  // Toast notification helper
  const showToast = (title, message, type = 'info') => {
    const toast = document.createElement('div');
    toast.className = 'toast-notification';
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

  return (
    <Layout>
      <Header title="Add Document" showBack={step !== 'upload'} />
      <main className="max-w-xl mx-auto px-4 pt-6 lg:max-w-4xl lg:px-8">
          {step === 'upload' && (
            <div className="animate-in fade-in slide-in-from-bottom-4 duration-500">
              {/* Centered Smart Scan Section */}
              <div className="flex flex-col items-center justify-center py-8">
              <div className="text-center mb-12">
                <div className="inline-flex items-center justify-center w-24 h-24 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-3xl mb-6 shadow-2xl shadow-blue-500/30">
                  <span className="material-symbols-outlined text-white text-5xl">document_scanner</span>
                </div>
                <h1 className="text-4xl font-black text-slate-900 dark:text-slate-100 tracking-tight">
                  SMART <span className="text-blue-600 NOT-italic">SCAN</span>
                </h1>
                <p className="text-slate-500 text-base mt-3 font-medium max-w-md">Upload your invoice and we'll automatically extract all warranty details</p>
              </div>

              <div
                onClick={() => fileInputRef.current?.click()}
                className={cn(
                  "group relative border-2 border-dashed rounded-3xl p-16 flex flex-col items-center justify-center transition-all duration-500 cursor-pointer overflow-hidden w-full max-w-lg",
                  selectedFile
                    ? "border-blue-400 bg-blue-50 dark:border-blue-500 dark:bg-blue-900/20"
                    : "border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-900 hover:border-blue-400 hover:bg-slate-50 dark:hover:bg-slate-800/50"
                )}
              >
                {previewUrl ? (
                  <div className="absolute inset-0 z-0">
                    <img src={previewUrl} alt="Preview" className="w-full h-full object-cover opacity-20 grayscale" />
                  </div>
                ) : null}

                <div className="relative z-10 text-center">
                  <div className="size-20 bg-blue-100 dark:bg-blue-900/40 text-blue-600 rounded-3xl flex items-center justify-center mb-6 mx-auto group-hover:scale-110 group-hover:rotate-3 transition-transform duration-500">
                    <span className="material-symbols-outlined text-4xl">upload_file</span>
                  </div>
                  <h3 className="text-lg font-bold text-slate-900 dark:text-slate-100 mb-2">
                    {selectedFile ? selectedFile.name : 'Drop your invoice here'}
                  </h3>
                  <p className="text-xs text-slate-400 font-semibold uppercase tracking-widest">PDF, JPG or PNG</p>
                </div>
              </div>

              <input ref={fileInputRef} type="file" accept="image/*,.pdf" onChange={handleFileSelect} className="hidden" />

              <div className="mt-8 space-y-4 w-full max-w-lg">
                {selectedFile ? (
                  <Button onClick={handleStartOcr} className="w-full py-4 text-lg shadow-xl shadow-blue-500/20 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700">
                    <span className="material-symbols-outlined mr-2">auto_awesome</span>
                    Magic Scan ✨
                  </Button>
                ) : (
                  <button
                    onClick={() => {
                      setIsPrefilledFromScan(false);
                      setStep('manual');
                    }}
                    className="w-full py-4 px-6 bg-white dark:bg-slate-800 border-2 border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-200 font-bold rounded-xl hover:border-blue-400 hover:bg-slate-50 dark:hover:bg-slate-700 transition-all"
                  >
                    <span className="material-symbols-outlined mr-2">edit</span>
                    Enter Details Manually
                  </button>
                )}
              </div>
            </div>
          </div>
        )}

        {step === 'scanning' && (
          <div className="text-center py-10 animate-in zoom-in-95 duration-700 flex flex-col items-center justify-center min-h-[60vh]">
            {previewUrl && (
              <div className="max-w-[240px] mx-auto mb-8 rounded-2xl overflow-hidden shadow-2xl border-4 border-blue-500/20 animate-scanning relative">
                <img src={previewUrl} alt="Scanning" className="w-full h-auto opacity-60 grayscale" />
              </div>
            )}

            <div className="relative inline-block mt-4">
              <div className="w-36 h-36 border-4 border-slate-100 dark:border-slate-800 rounded-full"></div>
              <div className="absolute inset-0 border-4 border-t-blue-500 border-r-transparent border-b-transparent border-l-transparent rounded-full animate-spin"></div>
              <div className="absolute inset-6 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-full flex items-center justify-center shadow-xl shadow-blue-500/30">
                <span className="material-symbols-outlined text-white text-5xl animate-pulse">document_scanner</span>
              </div>
            </div>

            <h2 className="text-3xl font-black mt-8 text-slate-900 dark:text-slate-100">Analyzing Invoice...</h2>
            <p className="text-slate-500 text-base mt-3 font-medium max-w-md">Extracting product details, warranties and pricing information</p>

            <div className="mt-12 max-w-sm mx-auto space-y-3">
              {[
                { label: 'Document Analysis', done: true },
                { label: 'Product Recognition', done: !!ocrData?.product_name || (ocrData?.items?.length || 0) > 0 },
                {
                  label: 'Warranty Detection',
                  done: !!ocrData?.warranty_duration ||
                    (ocrData?.warranties?.length || 0) > 0 ||
                    (ocrData?.items || []).some((item) => (item.warranties?.length || 0) > 0),
                },
              ].map((task, i) => (
                <div key={i} className="flex items-center gap-3 bg-white dark:bg-slate-900 p-4 rounded-xl border border-slate-100 dark:border-slate-800 text-left shadow-sm">
                  <span className={cn(
                    "material-symbols-outlined text-sm rounded-full p-1.5",
                    task.done ? "bg-emerald-100 text-emerald-600" : "bg-slate-100 text-slate-300"
                  )}>
                    {task.done ? 'check_circle' : 'hourglass_bottom'}
                  </span>
                  <span className={cn("text-sm font-bold", task.done ? "text-slate-700 dark:text-slate-200" : "text-slate-400")}>
                    {task.label}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Review & Manual forms */}
        {(step === 'review' || step === 'manual') && (
          <div className="animate-in fade-in slide-in-from-right-8 duration-500">
            <Card className="p-8 relative overflow-hidden">
              <div className="absolute top-0 left-0 right-0 h-2 bg-primary"></div>
              <div className="flex items-center justify-between mb-8">
                <h3 className="text-xl font-black text-slate-900 dark:text-slate-100">
                  {step === 'review' ? 'Verify Details' : 'Manual Entry'}
                </h3>
                <span className="text-[10px] font-black uppercase tracking-widest bg-slate-100 px-2 py-1 rounded">
                  Step 2 of 2
                </span>
              </div>

              <form onSubmit={handleSubmit(handleFinalSubmit)} className="space-y-5">
                {(scanInsights.warnings.length > 0 || scanInsights.missingFields.length > 0) && (
                  <div className="space-y-3">
                    {scanInsights.warnings.length > 0 && (
                      <div className="p-4 bg-amber-50 border border-amber-200 rounded-xl">
                        <div className="flex items-start gap-3">
                          <span className="material-symbols-outlined text-amber-500 text-base mt-0.5">warning</span>
                          <div className="space-y-1">
                            <p className="text-xs font-black uppercase tracking-widest text-amber-700">AI Warnings</p>
                            {scanInsights.warnings.map((warning, index) => (
                              <p key={`${warning}-${index}`} className="text-sm text-amber-800 font-medium">{warning}</p>
                            ))}
                          </div>
                        </div>
                      </div>
                    )}

                    {scanInsights.missingFields.length > 0 && (
                      <div className="p-4 bg-slate-50 border border-slate-200 rounded-xl">
                        <p className="text-xs font-black uppercase tracking-widest text-slate-500 mb-2">Needs Review</p>
                        <div className="flex flex-wrap gap-2">
                          {scanInsights.missingFields.map((field) => (
                            <span
                              key={field}
                              className="inline-flex items-center rounded-full bg-white border border-slate-200 px-3 py-1 text-xs font-bold text-slate-700"
                            >
                              {field.replace(/_/g, ' ')}
                            </span>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                )}

                {submitError && (
                  <div className="p-4 bg-red-50 border border-red-200 rounded-xl flex items-start gap-3">
                    <span className="material-symbols-outlined text-red-500 text-base mt-0.5">error</span>
                    <p className="text-sm text-red-700 font-medium">{submitError}</p>
                  </div>
                )}

                {step === 'manual' && !isPrefilledFromScan && (
                  <div className="space-y-2 rounded-2xl border border-slate-200 dark:border-slate-700 p-4 bg-slate-50/60 dark:bg-slate-900/40">
                    <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Invoice File (Optional)</label>
                    <input
                      type="file"
                      accept=".pdf,.jpg,.jpeg,.png,image/jpeg,image/png,application/pdf"
                      onChange={handleManualInvoiceSelect}
                      className="block w-full rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 px-4 py-3 text-sm font-medium text-slate-700 dark:text-slate-200 file:mr-3 file:rounded-lg file:border-0 file:bg-primary/10 file:px-3 file:py-2 file:text-xs file:font-bold file:text-primary"
                    />
                    <p className="text-xs text-slate-500">
                      {selectedFile
                        ? `Selected file: ${selectedFile.name}`
                        : 'Upload PDF, JPG, or PNG (max 10MB).'}
                    </p>
                    {invoiceFileError && (
                      <p className="text-xs font-bold text-red-600">{invoiceFileError}</p>
                    )}
                  </div>
                )}
                <div className="space-y-1">
                  <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Purchase Context</label>
                  <div className="grid grid-cols-2 gap-4">
                    <Input type="date" {...register('purchase_date', { required: true })} />
                    <Input
                      type="text"
                      inputMode="decimal"
                      placeholder="Invoice Total"
                      {...register('invoice_amount', {
                        onChange: (event) => {
                          event.target.value = sanitizePriceInput(event.target.value);
                        },
                      })}
                    />
                  </div>
                </div>

                <div className="space-y-1">
                  <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Invoice Number</label>
                  <Input placeholder="Invoice # (optional)" {...register('invoice_number')} />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-1">
                    <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Seller</label>
                    <Input placeholder="Where was it bought?" {...register('seller_name', { required: true })} />
                  </div>
                  <div className="space-y-1">
                    <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Platform</label>
                    <Input placeholder="Flipkart, Amazon..." {...register('platform_name')} />
                  </div>
                </div>

                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Products</label>
                    <button type="button" className="text-xs font-bold text-primary" onClick={addReviewItem}>
                      Add Product
                    </button>
                  </div>

                  {reviewItems.map((item, itemIndex) => (
                    <div key={item.id} className="rounded-2xl border border-slate-200 dark:border-slate-700 p-4 space-y-4 bg-slate-50/50 dark:bg-slate-900/40">
                      <div className="flex items-center justify-between">
                        <p className="text-xs font-black uppercase tracking-widest text-slate-500">Product {itemIndex + 1}</p>
                        <button
                          type="button"
                          className="text-xs font-bold text-slate-400 hover:text-red-500 disabled:opacity-40"
                          disabled={reviewItems.length <= 1}
                          onClick={() => removeReviewItem(item.id)}
                        >
                          Remove Product
                        </button>
                      </div>

                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-1">
                          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Product Name</label>
                          <Input
                            placeholder="What did you buy?"
                            value={item.product_name}
                            onChange={(e) => updateReviewItem(item.id, 'product_name', e.target.value)}
                          />
                        </div>
                        <div className="space-y-1">
                          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Brand</label>
                          <Input
                            placeholder="Apple, Sony..."
                            value={item.brand}
                            onChange={(e) => updateReviewItem(item.id, 'brand', e.target.value)}
                          />
                        </div>
                      </div>

                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-1">
                          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Model #</label>
                          <Input
                            placeholder="Optional"
                            value={item.model_number}
                            onChange={(e) => updateReviewItem(item.id, 'model_number', e.target.value)}
                          />
                        </div>
                        <div className="space-y-1">
                          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Price</label>
                          <Input
                            type="text"
                            inputMode="decimal"
                            placeholder="Item price"
                            value={item.price ?? ''}
                            onChange={(e) => updateReviewItem(item.id, 'price', sanitizePriceInput(e.target.value))}
                          />
                        </div>
                      </div>

                      <div className="space-y-1">
                        <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Category</label>
                        <select
                          value={item.category || 'Other'}
                          onChange={(e) => updateReviewItem(item.id, 'category', e.target.value)}
                          className="w-full px-4 py-3 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl focus:ring-2 focus:ring-primary outline-none transition-all font-bold text-sm"
                        >
                          <option value="Handsets">Handsets</option>
                          <option value="Electronics">Electronics</option>
                          <option value="Appliances">Appliances</option>
                          <option value="Kitchenware">Kitchenware</option>
                          <option value="Furniture">Furniture</option>
                          <option value="Tools">Tools</option>
                          <option value="Automotive">Automotive</option>
                          <option value="Other">Other</option>
                        </select>
                      </div>

                      <div className="space-y-3">
                        <div className="flex items-center justify-between">
                          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Warranties</label>
                          <button
                            type="button"
                            className="text-xs font-bold text-primary"
                            onClick={() => addReviewWarranty(item.id)}
                          >
                            Add Warranty
                          </button>
                        </div>

                        {(item.warranties || []).map((warranty, warrantyIndex) => (
                          <div key={`${item.id}-${warrantyIndex}`} className="space-y-3">
                            <div className="grid grid-cols-[1fr_auto] gap-3 items-start">
                              <Input
                                placeholder="Component"
                                value={warranty.component || ''}
                                onChange={(e) => updateReviewWarranty(item.id, warrantyIndex, 'component', e.target.value)}
                              />
                              <button
                                type="button"
                                className="text-xs font-bold text-slate-400 hover:text-red-500 disabled:opacity-40 mt-7"
                                disabled={(item.warranties || []).length <= 1}
                                onClick={() => removeReviewWarranty(item.id, warrantyIndex)}
                              >
                                Remove
                              </button>
                            </div>
                            <div className="space-y-2">
                              <label className="text-xs font-bold text-slate-600">Warranty Duration</label>
                              <div className="grid grid-cols-2 gap-3">
                                <div>
                                  <label className="text-[10px] text-slate-500 block mb-1">Years</label>
                                  <input
                                    type="number"
                                    value={monthsToYearsAndMonths(warranty.duration_months).years}
                                    onChange={(e) => {
                                      const months = yearsAndMonthsToMonths(e.target.value, monthsToYearsAndMonths(warranty.duration_months).months);
                                      updateReviewWarranty(item.id, warrantyIndex, 'duration_months', months || null);
                                    }}
                                    placeholder="0"
                                    min="0"
                                    className="w-full px-3 py-2 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg text-sm"
                                  />
                                </div>
                                <div>
                                  <label className="text-[10px] text-slate-500 block mb-1">Months</label>
                                  <input
                                    type="number"
                                    value={monthsToYearsAndMonths(warranty.duration_months).months}
                                    onChange={(e) => {
                                      const months = yearsAndMonthsToMonths(monthsToYearsAndMonths(warranty.duration_months).years, e.target.value);
                                      updateReviewWarranty(item.id, warrantyIndex, 'duration_months', months || null);
                                    }}
                                    placeholder="0"
                                    min="0"
                                    max="11"
                                    className="w-full px-3 py-2 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg text-sm"
                                  />
                                </div>
                              </div>
                              <p className="text-xs text-slate-400 mt-2">
                                {monthsToYearsAndMonths(warranty.duration_months).display}
                              </p>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>

                <div className="pt-8 flex flex-col gap-3">
                  <Button type="submit" className="w-full py-4 text-lg" disabled={isSubmitting}>
                    {isSubmitting ? 'Saving...' : 'Finish & Save'}
                  </Button>
                  <button type="button" onClick={() => setStep('upload')} className="text-slate-400 text-xs font-bold hover:text-slate-600">
                    Go Back
                  </button>
                </div>
              </form>
            </Card>

            {ocrError && (
              <div className="mt-6 p-6 bg-red-50 border-2 border-red-300 dark:bg-red-900/20 dark:border-red-700 rounded-2xl">
                <div className="flex items-start gap-4">
                  <div className="flex-shrink-0">
                    <span className="material-symbols-outlined text-red-500 text-3xl">error</span>
                  </div>
                  <div className="flex-1">
                    <h4 className="text-base font-black text-red-800 dark:text-red-200 mb-2">Scan Failed</h4>
                    <p className="text-sm text-red-700 dark:text-red-300 font-medium mb-4">{ocrError}</p>

                    {scanInsights.missingFields.length > 0 && (
                      <div className="mt-4 p-4 bg-white dark:bg-slate-800 rounded-xl border border-red-200 dark:border-red-800">
                        <p className="text-xs font-bold text-red-800 dark:text-red-200 mb-3 uppercase tracking-wider">Missing Required Fields:</p>
                        <div className="flex flex-wrap gap-2">
                          {scanInsights.missingFields.map((field) => (
                            <span
                              key={field}
                              className="inline-flex items-center gap-1 rounded-lg bg-red-100 dark:bg-red-900/40 border border-red-300 dark:border-red-700 px-3 py-2 text-sm font-bold text-red-800 dark:text-red-200"
                            >
                              <span className="material-symbols-outlined text-sm">close</span>
                              {field.replace(/_/g, ' ')}
                            </span>
                          ))}
                        </div>
                        <div className="mt-4 pt-4 border-t border-red-200 dark:border-red-800">
                          <p className="text-xs text-slate-600 dark:text-slate-300">
                            <strong>What to do:</strong> Your invoice image doesn't contain these required fields.
                            Please re-upload a clearer invoice, or use the manual entry form below to add the details.
                          </p>
                        </div>
                      </div>
                    )}

                    <div className="mt-4 flex gap-3">
                      <button
                        type="button"
                        onClick={() => setStep('upload')}
                        className="flex-1 py-3 px-4 bg-white dark:bg-slate-800 border-2 border-red-300 dark:border-red-700 text-red-700 dark:text-red-300 font-bold rounded-xl hover:bg-red-50 dark:hover:bg-red-900/30 transition-all"
                      >
                        <span className="material-symbols-outlined mr-2 text-sm">refresh</span>
                        Re-upload Invoice
                      </button>
                      <button
                        type="button"
                        onClick={() => setOcrError(null)}
                        className="flex-1 py-3 px-4 bg-red-600 text-white font-bold rounded-xl hover:bg-red-700 transition-all shadow-lg shadow-red-600/30"
                      >
                        <span className="material-symbols-outlined mr-2 text-sm">edit</span>
                        Enter Manually
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </main>
    </Layout>
  );
}
