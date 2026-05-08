import { useState, useEffect, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import useInvoiceStore from '../store/invoiceStore';
import { Layout } from '../components/Layout';
import { Header } from '../components/Header';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { Card } from '../components/Card';
import { cn } from '../utils/cn';
import { monthsToYearsAndMonths, yearsAndMonthsToMonths } from '../utils/warrantyDurationHelper';

export function EditProduct() {
    const { id } = useParams();
    const navigate = useNavigate();
    const { fetchInvoice, updateInvoice, loading: storeLoading } = useInvoiceStore();

    const [invoice, setInvoice] = useState(null);
    const [loading, setLoading] = useState(true);
    const [selectedFile, setSelectedFile] = useState(null);
    const [previewUrl, setPreviewUrl] = useState(null);
    const [warrantyFields, setWarrantyFields] = useState([]);
    const fileInputRef = useRef(null);

    const { register, handleSubmit, setValue, formState: { errors, isDirty } } = useForm();

    useEffect(() => {
        const loadInvoice = async () => {
            // Only load if we have a valid ID
            if (!id || id === 'undefined') {
                console.error('Invalid invoice ID:', id);
                navigate('/dashboard');
                return;
            }

            setLoading(true);
            const data = await fetchInvoice(id);
            if (data) {
                setInvoice(data);

                // Pre-fill form with existing invoice data
                // Handle purchase_date - extract date part only
                if (data.purchase_date) {
                    const purchaseDate = typeof data.purchase_date === 'string'
                        ? data.purchase_date.split('T')[0]
                        : data.purchase_date;
                    setValue('purchase_date', purchaseDate);
                }

                // Set product fields from first item (if available)
                if (data.items && data.items.length > 0) {
                    const firstItem = data.items[0];
                    setValue('product_name', firstItem.product_name || '');
                    setValue('brand', firstItem.brand || '');
                    setValue('model_number', firstItem.model || firstItem.model_number || '');
                    setValue('category', firstItem.category || 'Other');
                    if (firstItem.price) {
                        setValue('amount', firstItem.price);
                    }
                } else {
                    // Fallback to top-level fields
                    setValue('product_name', data.product_name || '');
                    setValue('brand', data.brand || '');
                    setValue('model_number', data.model || data.model_number || '');
                    setValue('category', data.category || 'Other');
                }

                // Set invoice-level fields
                setValue('seller', data.seller_name || '');
                setValue('invoice_number', data.invoice_number || '');

                // Build warranty fields from existing warranties
                const firstItem = data.items?.[0];
                if (firstItem) {
                    const warranties = firstItem.warranties || firstItem.item_warranties || [];
                    const fields = warranties.map(w => ({
                        id: w.id,
                        component: w.component_display || w.component || w.component_name || 'Product',
                        component_name: w.component_name || w.component || 'product',
                        duration_months: w.duration_months || '',
                        original_duration: w.duration_months
                    }));
                    setWarrantyFields(fields.length > 0 ? fields : []);
                }

                // Set total amount if amount wasn't set from item
                if (data.total_amount && !data.items?.length) {
                    setValue('amount', data.total_amount);
                }
            } else {
                // Invoice not found, redirect to dashboard
                console.error('Invoice not found for ID:', id);
                navigate('/dashboard');
            }
            setLoading(false);
        };
        loadInvoice();
    }, [id, setValue, navigate, fetchInvoice]);

    // Real-time updates: poll every 30 seconds (only if not editing)
    useEffect(() => {
        if (!id) return;

        const interval = setInterval(async () => {
            // Only update if form is not dirty (user is actively editing)
            if (!isDirty) {
                const data = await fetchInvoice(id);
                if (data) {
                    setInvoice(data);
                }
            }
        }, 30000); // 30 seconds

        return () => clearInterval(interval);
    }, [id, isDirty]);

    const handleFileSelect = (e) => {
        const file = e.target.files[0];
        if (file) {
            setSelectedFile(file);
            const url = window.URL.createObjectURL(file);
            setPreviewUrl(url);
        }
    };

    const onSubmit = async (data) => {
        const formData = new FormData();

        // Send nested under invoice[] -- same structure as create (InvoiceWorkflow)
        formData.append('invoice[purchase_date]', data.purchase_date || '');
        formData.append('invoice[invoice_number]', data.invoice_number || '');
        formData.append('invoice[seller]', data.seller_name || '');
        formData.append('invoice[total_amount]', data.amount || '');
        formData.append('invoice[product_name]', data.product_name || '');
        formData.append('invoice[brand]', data.brand || '');
        formData.append('invoice[model_number]', data.model_number || '');
        formData.append('invoice[category]', data.category || 'Other');

        // Include item ID so backend updates existing record instead of creating duplicate
        if (invoice?.items?.length > 0) {
            const item = invoice.items[0];
            formData.append('invoice[items][0][id]', item.id);
            formData.append('invoice[items][0][product_name]', data.product_name || '');
            formData.append('invoice[items][0][brand]', data.brand || '');
            formData.append('invoice[items][0][model_number]', data.model_number || '');
            formData.append('invoice[items][0][category]', data.category || 'Other');
            formData.append('invoice[items][0][price]', data.amount || '');
        }

        // Send each warranty with its ID and component so backend updates the specific one
        warrantyFields.forEach((warranty, index) => {
            if (warranty.id) {
                formData.append(`invoice[items][0][warranties][${index}][id]`, warranty.id);
                formData.append(`invoice[items][0][warranties][${index}][component_name]`, warranty.component_name);
                formData.append(`invoice[items][0][warranties][${index}][duration_months]`, warranty.duration_months || '');
            }
        });

        if (selectedFile) {
            formData.append('invoice[file]', selectedFile);
        }

        const result = await updateInvoice(id, formData);
        if (result.success) {
            navigate(`/invoice/${id}`);
        } else {
            alert(result.error);
        }
    };

    const hasWarrantyChanges = warrantyFields.some(
        w => String(w.duration_months) !== String(w.original_duration)
    );

    if (loading) return <LoadingSpinner />;
    if (!invoice) return <div className="p-8 text-center text-slate-500">Product not found.</div>;

    return (
    <Layout>
        <Header title="Edit Product" showBack />
        <main className="max-w-xl mx-auto px-4 pt-6 lg:max-w-4xl lg:px-8">
                    <div className="animate-in fade-in slide-in-from-bottom-4 duration-500">
                        <Card className="p-8 relative overflow-hidden">
                            <div className="absolute top-0 left-0 right-0 h-2 bg-primary"></div>

                            <div className="mb-8">
                                <h3 className="text-xl font-black text-slate-900 dark:text-slate-100">
                                    Update Information
                                </h3>
                                <p className="text-xs text-slate-500 mt-1 font-medium italic">Feel free to refine the product details or replace the receipt.</p>
                            </div>

                            <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
                                {/* Receipt Replacement Section */}
                                <div className="space-y-3">
                                    <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Receipt / Invoice</label>
                                    <div
                                        onClick={() => fileInputRef.current?.click()}
                                        className={cn(
                                            "relative border-2 border-dashed rounded-2xl p-6 flex flex-col items-center justify-center transition-all duration-300 cursor-pointer overflow-hidden group",
                                            selectedFile ? "border-primary/40 bg-primary/5" : "border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-900"
                                        )}
                                    >
                                        {previewUrl || invoice.file_url ? (
                                            <div className="absolute inset-0 z-0 opacity-10">
                                                <img
                                                    src={previewUrl || invoice.file_url}
                                                    alt="Background"
                                                    className="w-full h-full object-cover grayscale"
                                                />
                                            </div>
                                        ) : null}

                                        <div className="relative z-10 text-center">
                                            <span className="material-symbols-outlined text-3xl text-primary mb-2 block group-hover:scale-110 transition-transform">
                                                {selectedFile ? 'file_present' : 'receipt_long'}
                                            </span>
                                            <p className="text-xs font-bold text-slate-700 dark:text-slate-200">
                                                {selectedFile ? selectedFile.name : 'Replace Current Receipt?'}
                                            </p>
                                            <p className="text-[10px] text-slate-400 mt-1 uppercase font-black tracking-tighter">Click to browse</p>
                                        </div>
                                    </div>
                                    <input ref={fileInputRef} type="file" accept="image/*,.pdf" onChange={handleFileSelect} className="hidden" />
                                </div>

                                <div className="space-y-5">
                                    <div className="space-y-1">
                                        <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Invoice Number</label>
                                        <Input placeholder="INV-001" {...register('invoice_number')} />
                                    </div>

                                    <div className="space-y-1">
                                        <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Product Name</label>
                                        <Input placeholder="What did you buy?" {...register('product_name', { required: true })} />
                                    </div>

                                    <div className="grid grid-cols-2 gap-4">
                                        <div className="space-y-1">
                                            <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Brand</label>
                                            <Input placeholder="Apple, Sony..." {...register('brand')} />
                                        </div>
                                        <div className="space-y-1">
                                            <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Model #</label>
                                            <Input placeholder="Optional" {...register('model_number')} />
                                        </div>
                                    </div>

                                    <div className="space-y-1">
                                      <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Purchase Context</label>
                                      <div className="grid grid-cols-2 gap-4">
                                        <Input type="date" {...register('purchase_date', { required: true })} />

                                        {/* Price field with rupee symbol */}
                                        <div className="relative">
                                          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-600 dark:text-slate-400 font-semibold">₹</span>
                                          <Input
                                            type="number"
                                            placeholder="Price"
                                            step="0.01"
                                            {...register('amount')}
                                            className="pl-8"
                                          />
                                        </div>
                                      </div>
                                    </div>

                                    <div className="space-y-1">
                                        <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Category</label>
                                        <select {...register('category')} className="w-full px-4 py-3 bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl focus:ring-2 focus:ring-primary outline-none transition-all font-bold text-sm">
                                            <option value="Electronics">Electronics</option>
                                            <option value="Appliances">Appliances</option>
                                            <option value="Furniture">Furniture</option>
                                            <option value="Tools">Tools</option>
                                            <option value="Other">Other</option>
                                        </select>
                                    </div>

                                    {/* Warranties Section */}
                                    {warrantyFields.length > 0 && (
                                        <div className="space-y-3">
                                            <label className="text-[10px] font-black text-slate-400 uppercase ml-1">
                                                Warranties ({warrantyFields.length})
                                            </label>
                                            <div className="space-y-3">
                                                {warrantyFields.map((warranty, index) => {
                                                    const { years, months } = monthsToYearsAndMonths(warranty.duration_months);

                                                    return (
                                                        <div key={warranty.id || index} className="bg-white dark:bg-slate-800 rounded-xl p-6 border border-slate-200 dark:border-slate-700">
                                                            <p className="text-sm font-bold text-slate-900 dark:text-slate-100 mb-4 capitalize">{warranty.component} Coverage</p>

                                                            <div className="grid grid-cols-2 gap-4 mb-4">
                                                                <div>
                                                                    <label className="text-xs font-bold text-slate-600 dark:text-slate-400 block mb-2">Years</label>
                                                                    <input
                                                                        type="number"
                                                                        value={years}
                                                                        onChange={(e) => {
                                                                            const newMonths = yearsAndMonthsToMonths(e.target.value, months);
                                                                            const updated = [...warrantyFields];
                                                                            updated[index] = { ...updated[index], duration_months: newMonths };
                                                                            setWarrantyFields(updated);
                                                                        }}
                                                                        placeholder="0"
                                                                        min="0"
                                                                        className="w-full px-3 py-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-700 rounded-lg text-sm font-bold focus:ring-2 focus:ring-primary outline-none"
                                                                    />
                                                                </div>

                                                                <div>
                                                                    <label className="text-xs font-bold text-slate-600 dark:text-slate-400 block mb-2">Months</label>
                                                                    <input
                                                                        type="number"
                                                                        value={months}
                                                                        onChange={(e) => {
                                                                            const newMonths = yearsAndMonthsToMonths(years, e.target.value);
                                                                            const updated = [...warrantyFields];
                                                                            updated[index] = { ...updated[index], duration_months: newMonths };
                                                                            setWarrantyFields(updated);
                                                                        }}
                                                                        placeholder="0"
                                                                        min="0"
                                                                        max="11"
                                                                        className="w-full px-3 py-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-700 rounded-lg text-sm font-bold focus:ring-2 focus:ring-primary outline-none"
                                                                    />
                                                                </div>
                                                            </div>

                                                        </div>
                                                    );
                                                })}
                                            </div>
                                        </div>
                                    )}

                                    <div className="space-y-1">
                                        <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Retailer</label>
                                        <Input placeholder="Where was it bought?" {...register('seller')} />
                                    </div>
                                </div>

                                <div className="pt-8 flex flex-col gap-3">
                                    <Button type="submit" className="w-full py-4 text-lg shadow-xl shadow-primary/20" disabled={storeLoading || (!isDirty && !hasWarrantyChanges)}>
                                        {storeLoading ? 'Saving...' : (isDirty || hasWarrantyChanges) ? 'Save Changes' : 'No Changes to Save'}
                                    </Button>
                                    <button
                                        type="button"
                                        onClick={() => navigate(`/invoice/${id}`)}
                                        className="text-slate-400 text-xs font-bold hover:text-slate-600 transition-colors"
                                    >
                                        Cancel
                                    </button>
                                </div>
                            </form>
                    </Card>
                </div>
            </main>
    </Layout>
    );
}
