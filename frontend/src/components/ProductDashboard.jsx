import React, { useState, useEffect } from 'react';
import { Search, Filter, Calendar, AlertCircle, CheckCircle, Clock, Download, Eye, RefreshCw } from 'lucide-react';
import { invoicesAPI, isAuthenticated } from '../services/api';
import { getDefaultProductImage } from '../utils/productImageHelper';

const ProductDashboard = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState('all');
  const [selectedProduct, setSelectedProduct] = useState(null);
  const [showDetailModal, setShowDetailModal] = useState(false);

  useEffect(() => {
    loadProducts();
  }, []);

  async function loadProducts() {
    try {
      setLoading(true);
      const result = await invoicesAPI.getDashboard();

      if (result.success) {
        setProducts(result.products || []);
      }
    } catch (error) {
      if (isAuthenticated()) console.error('Failed to load products:', error);
    } finally {
      setLoading(false);
    }
  }

  function filteredProducts() {
    let filtered = products;

    // Search filter
    if (searchQuery) {
      filtered = filtered.filter(product =>
        product.product_name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        product.brand?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        product.category?.toLowerCase().includes(searchQuery.toLowerCase())
      );
    }

    // Status filter
    if (filterStatus !== 'all') {
      filtered = filtered.filter(product => {
        if (filterStatus === 'active') return product.warranty_status === 'active';
        if (filterStatus === 'expiring') return product.warranty_status === 'expiring_soon';
        if (filterStatus === 'expired') return product.warranty_status === 'expired';
        return true;
      });
    }

    return filtered;
  }

  function getWarrantyStatusIcon(status) {
    switch (status) {
      case 'active':
        return <CheckCircle className="w-5 h-5 text-green-500" />;
      case 'expiring_soon':
        return <AlertCircle className="w-5 h-5 text-yellow-500" />;
      case 'expired':
        return <Clock className="w-5 h-5 text-red-500" />;
      default:
        return <Clock className="w-5 h-5 text-gray-400" />;
    }
  }

  function getWarrantyStatusText(status, daysRemaining) {
    switch (status) {
      case 'active':
        return `Active (${daysRemaining} days left)`;
      case 'expiring_soon':
        return `Expiring in ${daysRemaining} days`;
      case 'expired':
        return `Expired ${Math.abs(daysRemaining)} days ago`;
      default:
        return 'Unknown';
    }
  }

  function getWarrantyStatusColor(status) {
    switch (status) {
      case 'active':
        return 'bg-green-100 text-green-800';
      case 'expiring_soon':
        return 'bg-yellow-100 text-yellow-800';
      case 'expired':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  }

  async function handleDownloadInvoice(invoiceId) {
    try {
      const response = await invoicesAPI.download(invoiceId);

      if (response.ok) {
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `invoice-${invoiceId}.pdf`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
      }
    } catch (error) {
      if (isAuthenticated()) console.error('Download failed:', error);
      alert('Failed to download invoice');
    }
  }

  function openProductDetail(product) {
    setSelectedProduct(product);
    setShowDetailModal(true);
  }

  function ProductCard({ product }) {
    return (
      <div className="bg-white rounded-lg shadow-sm border hover:shadow-md transition-shadow">
        {/* Product Image */}
        <div className="h-48 bg-gray-100 rounded-t-lg flex items-center justify-center">
          <img
            src={getDefaultProductImage(product.product_name, product.brand, product.product_image_url, product.category)}
            alt={product.product_name}
            className="h-full w-full object-cover rounded-t-lg"
          />
        </div>

        {/* Product Info */}
        <div className="p-4">
          <div className="mb-3">
            <h3 className="font-semibold text-lg text-gray-900 mb-1">
              {product.product_name}
            </h3>
            <p className="text-sm text-gray-600">
              {product.brand} {product.model_number && `• ${product.model_number}`}
            </p>
          </div>

          {/* Warranty Status */}
          <div className="mb-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center">
                {getWarrantyStatusIcon(product.warranty_status)}
                <span className={`ml-2 px-2 py-1 rounded-full text-xs font-medium ${getWarrantyStatusColor(product.warranty_status)}`}>
                  {getWarrantyStatusText(product.warranty_status, product.days_remaining)}
                </span>
              </div>
            </div>

            {product.expires_at && (
              <p className="text-xs text-gray-500 mt-1">
                Expires: {new Date(product.expires_at).toLocaleDateString()}
              </p>
            )}
          </div>

          {/* Purchase Info */}
          <div className="mb-4 text-sm text-gray-600">
            <p>Purchased: {product.purchase_date ? new Date(product.purchase_date).toLocaleDateString() : 'N/A'}</p>
            {product.amount && (
              <p>Amount: ${product.amount}</p>
            )}
            {product.seller && (
              <p>Seller: {product.seller}</p>
            )}
          </div>

          {/* Actions */}
          <div className="flex gap-2">
            <button
              onClick={() => openProductDetail(product)}
              className="flex-1 px-3 py-2 bg-blue-500 text-white text-sm rounded-lg hover:bg-blue-600"
            >
              View Details
            </button>
            {product.file_url && (
              <button
                onClick={() => handleDownloadInvoice(product.id)}
                className="px-3 py-2 bg-gray-100 text-gray-700 text-sm rounded-lg hover:bg-gray-200"
                title="Download Invoice"
              >
                <Download className="w-4 h-4" />
              </button>
            )}
          </div>
        </div>
      </div>
    );
  }

  function ProductDetailModal() {
    if (!selectedProduct) return null;

    return (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
        <div className="bg-white rounded-lg max-w-2xl w-full max-h-[90vh] overflow-y-auto">
          {/* Header */}
          <div className="p-6 border-b">
            <div className="flex justify-between items-start">
              <div>
                <h2 className="text-2xl font-bold">{selectedProduct.product_name}</h2>
                <p className="text-gray-600">{selectedProduct.brand} {selectedProduct.model_number}</p>
              </div>
              <button
                onClick={() => setShowDetailModal(false)}
                className="text-gray-400 hover:text-gray-600"
              >
                ×
              </button>
            </div>
          </div>

          {/* Content */}
          <div className="p-6">
            {/* Product Image */}
            <div className="mb-6">
              <img
                src={getDefaultProductImage(selectedProduct.product_name, selectedProduct.brand, selectedProduct.product_image_url, selectedProduct.category)}
                alt={selectedProduct.product_name}
                className="w-full h-64 object-cover rounded-lg"
              />
            </div>

            {/* Tabs */}
            <div className="border-b mb-6">
              <div className="flex space-x-8">
                <button className="pb-2 border-b-2 border-blue-500 text-blue-600 font-medium">
                  Overview
                </button>
                <button className="pb-2 text-gray-500 hover:text-gray-700">
                  Warranty
                </button>
                <button className="pb-2 text-gray-500 hover:text-gray-700">
                  Invoice
                </button>
              </div>
            </div>

            {/* Overview Tab */}
            <div className="space-y-4">
              <div>
                <h3 className="font-semibold mb-2">Product Information</h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-gray-500">Brand:</span>
                    <p className="font-medium">{selectedProduct.brand || 'N/A'}</p>
                  </div>
                  <div>
                    <span className="text-gray-500">Model:</span>
                    <p className="font-medium">{selectedProduct.model_number || 'N/A'}</p>
                  </div>
                  <div>
                    <span className="text-gray-500">Category:</span>
                    <p className="font-medium capitalize">{selectedProduct.category || 'N/A'}</p>
                  </div>
                  <div>
                    <span className="text-gray-500">Seller:</span>
                    <p className="font-medium">{selectedProduct.seller || 'N/A'}</p>
                  </div>
                </div>
              </div>

              {selectedProduct.product_description && (
                <div>
                  <h3 className="font-semibold mb-2">Description</h3>
                  <p className="text-sm text-gray-600">{selectedProduct.product_description}</p>
                </div>
              )}

              <div>
                <h3 className="font-semibold mb-2">Purchase Details</h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-gray-500">Purchase Date:</span>
                    <p className="font-medium">
                      {selectedProduct.purchase_date ? new Date(selectedProduct.purchase_date).toLocaleDateString() : 'N/A'}
                    </p>
                  </div>
                  <div>
                    <span className="text-gray-500">Amount:</span>
                    <p className="font-medium">${selectedProduct.amount || 'N/A'}</p>
                  </div>
                </div>
              </div>

              {/* Component Warranties */}
              {selectedProduct.warranties && selectedProduct.warranties.length > 0 && (
                <div>
                  <h3 className="font-semibold mb-2">Component Warranties</h3>
                  <div className="space-y-2">
                    {selectedProduct.warranties.map((warranty, index) => (
                      <div key={index} className="flex justify-between items-center p-3 bg-gray-50 rounded">
                        <div>
                          <p className="font-medium capitalize">{warranty.component_name}</p>
                          <p className="text-sm text-gray-600">{warranty.warranty_months} months</p>
                        </div>
                        <div className="text-right">
                          <p className="text-sm font-medium">
                            {warranty.expires_at ? new Date(warranty.expires_at).toLocaleDateString() : 'N/A'}
                          </p>
                          <p className={`text-xs ${warranty.active ? 'text-green-600' : warranty.expired ? 'text-red-600' : 'text-yellow-600'}`}>
                            {warranty.active ? 'Active' : warranty.expired ? 'Expired' : 'Expiring Soon'}
                          </p>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Invoice Actions */}
              {selectedProduct.file_url && (
                <div>
                  <h3 className="font-semibold mb-2">Invoice</h3>
                  <button
                    onClick={() => handleDownloadInvoice(selectedProduct.id)}
                    className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 flex items-center"
                  >
                    <Download className="w-4 h-4 mr-2" />
                    Download Invoice
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto p-6">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-3xl font-bold mb-2">Product Dashboard</h1>
        <p className="text-gray-600">Track your products and warranty information</p>
      </div>

      {/* Search and Filters */}
      <div className="mb-6 flex flex-col sm:flex-row gap-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input
            type="text"
            placeholder="Search products, brands, or categories..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <div className="flex gap-2">
          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
            className="px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="all">All Status</option>
            <option value="active">Active Warranty</option>
            <option value="expiring">Expiring Soon</option>
            <option value="expired">Expired</option>
          </select>

          <button
            onClick={loadProducts}
            className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200"
            title="Refresh"
          >
            <RefreshCw className="w-5 h-5" />
          </button>
        </div>
      </div>

      {/* Loading State */}
      {loading && (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
          <p className="mt-2 text-gray-600">Loading products...</p>
        </div>
      )}

      {/* Products Grid */}
      {!loading && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {filteredProducts().map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>
      )}

      {/* Empty State */}
      {!loading && filteredProducts().length === 0 && (
        <div className="text-center py-12">
          <div className="w-16 h-16 mx-auto mb-4 bg-gray-100 rounded-full flex items-center justify-center">
            <Eye className="w-8 h-8 text-gray-400" />
          </div>
          <h3 className="text-lg font-semibold mb-2">No products found</h3>
          <p className="text-gray-600 mb-4">
            {searchQuery || filterStatus !== 'all'
              ? 'Try adjusting your search or filters'
              : 'Start by adding your first product or invoice'}
          </p>
          {!searchQuery && filterStatus === 'all' && (
            <a href="/workflow" className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600">
              Add Product
            </a>
          )}
        </div>
      )}

      {/* Detail Modal */}
      {showDetailModal && <ProductDetailModal />}
    </div>
  );
};

export default ProductDashboard;
