import React, { useState } from 'react';
import { useDropzone } from 'react-dropzone';
import {
  Upload, FileText, Loader2, CheckCircle, AlertCircle,
  RefreshCw, Plus, Trash2, ChevronDown, ChevronUp, Package, ShieldCheck
} from 'lucide-react';
import { invoicesAPI } from '../services/api';

const InvoiceWorkflow = () => {
  const [uploadMode, setUploadMode] = useState('file'); // 'file' or 'manual'
  const [processingStatus, setProcessingStatus] = useState(null);
  const [errorMessage, setErrorMessage] = useState(null);
  const [currentInvoice, setCurrentInvoice] = useState(null);

  // Global Invoice Info
  const [globalForm, setGlobalForm] = useState({
    seller: '',
    invoice_number: '',
    purchase_date: '',
    total_amount: '',
    category: ''
  });

  // Dynamic Items Array
  const [items, setItems] = useState([
    {
      id: Date.now(),
      product_name: '',
      brand: '',
      model_number: '',
      category: 'Electronics',
      description: '',
      specifications: {},
      warranties: [
        { id: Date.now() + 1, component: 'product', duration_months: 12 }
      ],
      isExpanded: true
    }
  ]);

  const [uploadedFile, setUploadedFile] = useState(null);
  const [isPrefilledFromScan, setIsPrefilledFromScan] = useState(false);
  const [missingFields, setMissingFields] = useState([]);
  const [missingOptionalFields, setMissingOptionalFields] = useState([]);
  const [manualFileError, setManualFileError] = useState(null);

  const MAX_MANUAL_FILE_SIZE = 10 * 1024 * 1024; // 10MB
  const ALLOWED_MANUAL_FILE_TYPES = ['application/pdf', 'image/jpeg', 'image/png'];

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    accept: {
      'application/pdf': ['.pdf'],
      'image/jpeg': ['.jpg', '.jpeg'],
      'image/png': ['.png']
    },
    multiple: false,
    onDrop: handleFileUpload
  });

  async function handleFileUpload(files) {
    const file = files[0];
    if (!file) return;

    setUploadedFile(file);

    try {
      setProcessingStatus('uploading');
      setErrorMessage(null);

      const formData = new FormData();
      formData.append('file', file);

      const result = await invoicesAPI.scan(formData);
      const resData = result.data;

      if (resData.success) {
        const inv = resData.data || resData.invoice || {};

        // Populate Global Data
        setGlobalForm({
          seller: inv.seller || '',
          invoice_number: inv.invoice_number || '',
          purchase_date: inv.purchase_date ? inv.purchase_date.split('T')[0] : '',
          total_amount: inv.amount || inv.total_amount || '',
          category: inv.category || inv.product_category || 'General'
        });

        // Populate Items Data
        if (inv.items && Array.isArray(inv.items) && inv.items.length > 0) {
          setItems(inv.items.map((item, idx) => ({
            ...item,
            id: Date.now() + idx,
            isExpanded: idx === 0,
            warranties: (item.warranties && item.warranties.length > 0)
              ? item.warranties.map((w, wIdx) => ({ ...w, id: Date.now() + idx + wIdx + 100 }))
              : [{ id: Date.now() + idx + 200, component: 'product', duration_months: 12 }]
          })));
        }

        // Set missing fields for display
        setMissingFields(resData.missing_fields || []);
        setMissingOptionalFields(inv.missing_optional_fields || []);

        if (resData.warnings && resData.warnings.length > 0) {
          setErrorMessage(resData.warnings.join(' '));
        }

        setProcessingStatus(null);
        setIsPrefilledFromScan(true);
        setUploadMode('manual');
      } else {
        setProcessingStatus('error');
        setIsPrefilledFromScan(false);
        setErrorMessage(resData.error || "Upload failed.");
      }
    } catch (error) {
      setProcessingStatus('error');
      setIsPrefilledFromScan(false);
      setErrorMessage(error.response?.data?.error || 'Extraction failed: ' + error.message);
    }
  }

  function handleManualInvoiceFileChange(event) {
    const file = event.target.files?.[0];
    setManualFileError(null);

    if (!file) {
      setUploadedFile(null);
      return;
    }

    if (!ALLOWED_MANUAL_FILE_TYPES.includes(file.type)) {
      setManualFileError('Only PDF, JPG, and PNG files are allowed.');
      event.target.value = '';
      return;
    }

    if (file.size > MAX_MANUAL_FILE_SIZE) {
      setManualFileError('File size must be 10MB or less.');
      event.target.value = '';
      return;
    }

    setUploadedFile(file);
  }

  async function handleManualSubmit(e) {
    if (e) e.preventDefault();

    try {
      setProcessingStatus('processing');
      setErrorMessage(null);
      setMissingFields([]);
      setMissingOptionalFields([]);

      const formData = new FormData();

      formData.append('invoice[seller]', globalForm.seller);
      formData.append('invoice[invoice_number]', globalForm.invoice_number || '');
      formData.append('invoice[purchase_date]', globalForm.purchase_date);
      formData.append('invoice[total_amount]', globalForm.total_amount);

      if (uploadedFile) {
        formData.append('invoice[file]', uploadedFile);
      }

      items.forEach((item, index) => {
        formData.append(`invoice[items][${index}][product_name]`, item.product_name);
        formData.append(`invoice[items][${index}][brand]`, item.brand);
        formData.append(`invoice[items][${index}][model_number]`, item.model_number);
        formData.append(`invoice[items][${index}][category]`, item.category || 'General');
        formData.append(`invoice[items][${index}][description]`, item.description || '');
        formData.append(`invoice[items][${index}][specifications]`, JSON.stringify(item.specifications || {}));

        (item.warranties || []).forEach((w, wIdx) => {
          formData.append(`invoice[items][${index}][warranties][${wIdx}][component]`, w.component);
          formData.append(`invoice[items][${index}][warranties][${wIdx}][duration_months]`, w.duration_months);
        });
      });

      const result = await invoicesAPI.create(formData);

      if (result.status === 201 || result.data.success) {
        setCurrentInvoice(result.data.invoice);
        setProcessingStatus('completed');
        setErrorMessage(null);
      } else {
        setProcessingStatus('error');
        // Handle duplicate invoice error
        if (result.data.code === 'DUPLICATE_INVOICE') {
          setErrorMessage(result.data.details?.join(' ') || result.data.error || 'This invoice number already registered.');
        } else {
          setErrorMessage(result.data.error || "Submission failed.");
        }
      }
    } catch (error) {
      setProcessingStatus('error');
      const errorData = error.response?.data || {};
      // Handle duplicate invoice error from exception
      if (errorData.code === 'DUPLICATE_INVOICE') {
        setErrorMessage(errorData.details?.join(' ') || errorData.error || 'This invoice number is already registered in your account.');
      } else {
        setErrorMessage(error.response?.data?.error || 'Submission failed: ' + error.message);
      }
    }
  }

  const addItem = () => {
    setItems([...items, {
      id: Date.now(),
      product_name: '',
      brand: '',
      model_number: '',
      category: 'Electronics',
      warranties: [{ id: Date.now() + 1, component: 'product', duration_months: 12 }],
      isExpanded: true
    }]);
  };

  const removeItem = (id) => {
    if (items.length <= 1) return;
    setItems(items.filter(item => item.id !== id));
  };

  const updateItem = (id, field, value) => {
    setItems(items.map(item => item.id === id ? { ...item, [field]: value } : item));
  };

  const toggleExpand = (id) => {
    setItems(items.map(item => item.id === id ? { ...item, isExpanded: !item.isExpanded } : item));
  };

  const addWarranty = (itemId) => {
    setItems(items.map(item => {
      if (item.id === itemId) {
        return {
          ...item,
          warranties: [...item.warranties, { id: Date.now(), component: '', duration_months: 12 }]
        };
      }
      return item;
    }));
  };

  const updateWarranty = (itemId, warrantyId, field, value) => {
    setItems(items.map(item => {
      if (item.id === itemId) {
        return {
          ...item,
          warranties: item.warranties.map(w => w.id === warrantyId ? { ...w, [field]: value } : w)
        };
      }
      return item;
    }));
  };

  const removeWarranty = (itemId, warrantyId) => {
    setItems(items.map(item => {
      if (item.id === itemId) {
        return {
          ...item,
          warranties: item.warranties.filter(w => w.id !== warrantyId)
        };
      }
      return item;
    }));
  };

  return (
    <div className="max-w-5xl mx-auto p-6 animate-in fade-in duration-500">
      <div className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-3xl font-bold bg-gradient-to-r from-blue-600 to-indigo-600 bg-clip-text text-transparent">
            Add Product Vault
          </h1>
          <p className="text-gray-500 mt-1">Manage warranties for all your purchases in one place.</p>
        </div>
      </div>

      <div className="flex mb-8 bg-gray-100/80 backdrop-blur-sm rounded-xl p-1.5 shadow-inner">
        <button
          onClick={() => setUploadMode('file')}
          className={`flex-1 flex items-center justify-center py-3 px-4 rounded-lg transition-all duration-300 font-medium ${uploadMode === 'file' ? 'bg-white shadow-md text-blue-600' : 'text-gray-500 hover:text-gray-700'}`}
        >
          <Upload className="w-4 h-4 mr-2" /> AI Invoice Scan
        </button>
        <button
          onClick={() => { setUploadMode('manual'); setProcessingStatus(null); }}
          className={`flex-1 flex items-center justify-center py-3 px-4 rounded-lg transition-all duration-300 font-medium ${uploadMode === 'manual' ? 'bg-white shadow-md text-blue-600' : 'text-gray-500 hover:text-gray-700'}`}
        >
          <FileText className="w-4 h-4 mr-2" /> Multi-Product Entry
        </button>
      </div>

      {uploadMode === 'file' && !processingStatus && (
        <div className="bg-white rounded-2xl shadow-xl border border-blue-50 overflow-hidden">
          <div {...getRootProps()} className={`p-16 text-center cursor-pointer transition-all duration-300 ${isDragActive ? 'bg-blue-50/50' : 'hover:bg-gray-50'}`}>
            <input {...getInputProps()} />
            <div className="w-20 h-20 bg-blue-50 rounded-3xl flex items-center justify-center mx-auto mb-6">
              <Upload className="w-10 h-10 text-blue-500" />
            </div>
            <h3 className="text-xl font-semibold mb-2">Scan Your Invoice</h3>
            <p className="text-gray-500 mb-6 max-w-sm mx-auto">Drop your receipt here. Our AI will identify all items and warranties.</p>
          </div>
        </div>
      )}

      {uploadMode === 'manual' && (
        <div className="space-y-8 pb-12">
          {!isPrefilledFromScan && (
            <div className="bg-white rounded-2xl p-6 border shadow-sm">
              <h2 className="text-lg font-bold mb-4 flex items-center gap-2">
                <Upload className="w-5 h-5 text-blue-500" /> Upload Invoice (Optional)
              </h2>
              <input
                type="file"
                accept=".pdf,.jpg,.jpeg,.png"
                onChange={handleManualInvoiceFileChange}
                className="w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm"
              />
              <p className="mt-2 text-xs text-gray-500">
                Allowed: PDF, JPG, PNG. Max size: 10MB.
              </p>
              {uploadedFile && (
                <p className="mt-2 text-sm font-medium text-slate-700">
                  Selected: {uploadedFile.name}
                </p>
              )}
              {manualFileError && (
                <p className="mt-2 text-sm font-medium text-red-600">{manualFileError}</p>
              )}
            </div>
          )}

          {errorMessage && (
            <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex items-start gap-3">
              <AlertCircle className="w-5 h-5 text-amber-500 mt-0.5 flex-shrink-0" />
              <div className="flex-1">
                <h4 className="text-sm font-bold text-amber-800">Scanner Notice</h4>
                <p className="text-sm text-amber-700 mt-0.5">{errorMessage}</p>
              </div>
              <button onClick={() => setErrorMessage(null)} className="p-1 hover:bg-amber-100 rounded-lg"><Plus className="w-4 h-4 rotate-45 text-amber-500" /></button>
            </div>
          )}

          {missingFields.length > 0 && (
            <div className="bg-gray-100 border border-gray-200 rounded-2xl p-4 flex items-start gap-3">
              <AlertCircle className="w-5 h-5 text-gray-600 mt-0.5 flex-shrink-0" />
              <div className="flex-1">
                <h4 className="text-sm font-bold text-gray-800">Missing or Unclear Fields</h4>
                <p className="text-sm text-gray-700 mt-0.5">{missingFields.join(', ')}</p>
              </div>
            </div>
          )}

          {missingOptionalFields.length > 0 && (
            <div className="bg-blue-50 border border-blue-200 rounded-2xl p-4 flex items-start gap-3">
              <AlertCircle className="w-5 h-5 text-blue-600 mt-0.5 flex-shrink-0" />
              <div className="flex-1">
                <h4 className="text-sm font-bold text-blue-800">ℹ️ Incomplete Information After Scan</h4>
                <div className="text-sm text-blue-700 mt-0.5 space-y-1">
                  {missingOptionalFields.includes('price') && (
                    <p>• Price was not detected. Please add it manually to complete your warranty record.</p>
                  )}
                  {missingOptionalFields.includes('warranty') && (
                    <p>• Warranty details were not detected. Please add warranty information (duration, covered components) to ensure your products are properly covered.</p>
                  )}
                  {missingOptionalFields.includes('model_number') && (
                    <p>• Model number was not detected. Adding it will help identify your product more accurately.</p>
                  )}
                </div>
              </div>
            </div>
          )}

          <div className="bg-white rounded-2xl p-8 border shadow-sm">
            <h2 className="text-xl font-bold mb-6 flex items-center gap-2">
              <FileText className="w-5 h-5 text-blue-500" /> Invoice Summary
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-gray-400 uppercase">Seller</label>
                <input type="text" value={globalForm.seller} onChange={(e) => setGlobalForm({ ...globalForm, seller: e.target.value })} className="w-full px-4 py-3 bg-gray-50 rounded-xl" />
              </div>
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-gray-400 uppercase">Invoice #</label>
                <input type="text" value={globalForm.invoice_number} onChange={(e) => setGlobalForm({ ...globalForm, invoice_number: e.target.value })} className="w-full px-4 py-3 bg-gray-50 rounded-xl" />
              </div>
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-gray-400 uppercase">Date</label>
                <input type="date" value={globalForm.purchase_date} onChange={(e) => setGlobalForm({ ...globalForm, purchase_date: e.target.value })} className="w-full px-4 py-3 bg-gray-50 rounded-xl" />
              </div>
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-gray-400 uppercase">Total</label>
                <input type="number" value={globalForm.total_amount} onChange={(e) => setGlobalForm({ ...globalForm, total_amount: e.target.value })} className="w-full px-4 py-3 bg-gray-50 rounded-xl" />
              </div>
            </div>
          </div>

          <div className="space-y-6">
            <div className="flex justify-between items-end">
              <h2 className="text-2xl font-bold">Products</h2>
              <button onClick={addItem} className="flex items-center gap-2 px-4 py-2 bg-blue-50 text-blue-600 rounded-lg font-medium hover:bg-blue-100 transition-colors">
                <Plus className="w-4 h-4" /> Add Product
              </button>
            </div>

            {items.map((item, index) => (
              <div key={item.id} className="bg-white rounded-2xl border shadow-sm overflow-hidden">
                <div className="bg-gray-50/50 px-8 py-4 flex items-center justify-between border-b cursor-pointer" onClick={() => toggleExpand(item.id)}>
                  <div className="flex items-center gap-4">
                    <Package className="w-5 h-5 text-gray-400" />
                    <div>
                      <h3 className="font-bold text-gray-800">{item.product_name || `Product ${index + 1}`}</h3>
                      <p className="text-xs text-gray-500">{item.brand || 'No brand'}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-4">
                    {items.length > 1 && <button onClick={(e) => { e.stopPropagation(); removeItem(item.id); }} className="p-2 text-gray-400 hover:text-red-500"><Trash2 className="w-4 h-4" /></button>}
                    {item.isExpanded ? <ChevronUp className="w-5 h-5 text-gray-400" /> : <ChevronDown className="w-5 h-5 text-gray-400" />}
                  </div>
                </div>

                {item.isExpanded && (
                  <div className="p-8 space-y-8 animate-in slide-in-from-top-2">
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                      <div className="space-y-1.5">
                        <label className="text-xs font-bold text-gray-400 uppercase">Product Name</label>
                        <input type="text" value={item.product_name} onChange={(e) => updateItem(item.id, 'product_name', e.target.value)} className="w-full px-4 py-3 bg-gray-50 rounded-xl" />
                      </div>
                      <div className="space-y-1.5">
                        <label className="text-xs font-bold text-gray-400 uppercase">Brand</label>
                        <input type="text" value={item.brand} onChange={(e) => updateItem(item.id, 'brand', e.target.value)} className="w-full px-4 py-3 bg-gray-50 rounded-xl" />
                      </div>
                      <div className="space-y-1.5">
                        <label className="text-xs font-bold text-gray-400 uppercase">Model</label>
                        <input type="text" value={item.model_number} onChange={(e) => updateItem(item.id, 'model_number', e.target.value)} className="w-full px-4 py-3 bg-gray-50 rounded-xl" />
                      </div>
                    </div>

                    {item.specifications && Object.keys(item.specifications).length > 0 && (
                      <div className="flex flex-wrap gap-2">
                        {Object.entries(item.specifications).map(([key, value]) => (
                          <div key={key} className="bg-blue-50/50 border border-blue-100 rounded-lg px-3 py-1 text-blue-700 flex items-center gap-2">
                            <span className="text-[10px] font-extrabold uppercase text-blue-400">{key.replace('_', ' ')}</span>
                            <span className="font-semibold text-sm">{value}</span>
                          </div>
                        ))}
                      </div>
                    )}

                    <div className="bg-gray-50/50 rounded-2xl p-6 border border-gray-100">
                      <div className="flex justify-between items-center mb-6">
                        <h4 className="font-bold text-gray-700 text-sm uppercase">Warranty Details</h4>
                        <button onClick={() => addWarranty(item.id)} className="text-xs font-bold text-blue-600 bg-white px-3 py-1.5 rounded-lg border">+ Add Warranty</button>
                      </div>
                      <div className="space-y-3">
                        {item.warranties.map((w) => (
                          <div key={w.id} className="flex gap-4 items-center bg-white p-4 rounded-xl shadow-xs">
                            <input type="text" placeholder="Component" value={w.component} onChange={(e) => updateWarranty(item.id, w.id, 'component', e.target.value)} className="flex-1 px-3 py-2 text-sm border-transparent focus:ring-0" />
                            <input type="number" placeholder="Months" value={w.duration_months} onChange={(e) => updateWarranty(item.id, w.id, 'duration_months', e.target.value)} className="w-32 px-3 py-2 text-sm border-transparent focus:ring-0" />
                            <button disabled={item.warranties.length <= 1} onClick={() => removeWarranty(item.id, w.id)} className="p-2 text-gray-300 hover:text-red-400 transition-colors disabled:opacity-0"><Trash2 className="w-4 h-4" /></button>
                          </div>
                        ))}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            ))}
          </div>

          <div className="sticky bottom-8 bg-white/90 backdrop-blur-md p-6 rounded-3xl border shadow-2xl flex flex-col md:flex-row items-center justify-between gap-4">
            <div className="text-gray-500 text-sm">{items.length} Products detected.</div>
            <div className="flex gap-4 w-full md:w-auto">
              <button onClick={() => { setUploadMode('file'); setProcessingStatus(null); }} className="flex-1 md:px-8 py-4 bg-gray-100 text-gray-600 font-bold rounded-2xl">Cancel</button>
              <button onClick={handleManualSubmit} disabled={processingStatus === 'processing'} className="flex-[2] md:px-12 py-4 bg-blue-600 text-white font-bold rounded-2xl shadow-lg shadow-blue-600/30">
                {processingStatus === 'processing' ? 'Securing...' : 'Secure All to Vault'}
              </button>
            </div>
          </div>
        </div>
      )}

      {processingStatus && processingStatus !== 'processing' && (
        <div className="mt-8">
          {processingStatus === 'uploading' && (
            <div className="bg-white rounded-2xl p-12 text-center border shadow-xl flex flex-col items-center">
              <Loader2 className="w-12 h-12 text-blue-500 animate-spin mb-4" />
              <h3 className="text-xl font-bold mb-2">AI Analysis in Progress</h3>
              <p className="text-gray-500">Wait while we extract details from your invoice...</p>
            </div>
          )}
          {processingStatus === 'completed' && (
            <div className="bg-white rounded-2xl p-12 text-center border border-green-50 animate-in zoom-in">
              <CheckCircle className="w-12 h-12 text-green-500 mx-auto mb-6" />
              <h3 className="text-2xl font-bold mb-2">Successfully Vaulted!</h3>
              <button onClick={() => window.location.href = '/dashboard'} className="mt-8 px-12 py-4 bg-gray-900 text-white font-bold rounded-2xl">Go to Dashboard</button>
            </div>
          )}
          {processingStatus === 'error' && (
            <div className="bg-white rounded-2xl p-8 border border-red-50 shadow-xl">
              <div className="flex gap-6 mb-8">
                <AlertCircle className="w-12 h-12 text-red-500 flex-shrink-0" />
                <div><h3 className="text-xl font-bold mb-1">Scanning Issue</h3><p className="text-gray-500">{errorMessage}</p></div>
              </div>
              <div className="flex gap-4">
                <button onClick={() => { setUploadMode('file'); setProcessingStatus(null); }} className="flex-1 py-4 bg-gray-100 font-bold rounded-2xl"><RefreshCw className="w-4 h-4 mr-2 inline" /> Try Again</button>
                <button onClick={() => { setUploadMode('manual'); setProcessingStatus(null); }} className="flex-1 py-4 bg-blue-600 text-white font-bold rounded-2xl">Enter Manually</button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default InvoiceWorkflow;
