import React, { useState, useEffect } from 'react';
import './LoginModal.css';
import { API_BASE_URL } from '../config';

function LoginModal({ onClose, onLogin, initialStep = 'credentials', initialVectorStores = null, initialPendingCreds = null }) {
  const [formData, setFormData] = useState({
    casToken: '',
    endpoint: ''
  });
  const [showPassword, setShowPassword] = useState(false);
  const [isValidating, setIsValidating] = useState(false);
  const [error, setError] = useState('');

  // Step 2 state — shown after successful auth
  const [vectorStores, setVectorStores] = useState(initialStep === 'vector-store' ? initialVectorStores : null);
  const [selectedVectorStore, setSelectedVectorStore] = useState(
    initialStep === 'vector-store' && initialPendingCreds?.selectedVectorStore
      ? initialPendingCreds.selectedVectorStore
      : (initialStep === 'vector-store' && initialVectorStores?.[0]?.id) || ''
  );
  const [pendingCreds, setPendingCreds] = useState(initialStep === 'vector-store' ? initialPendingCreds : null);

  // Load endpoint from localStorage on mount
  useEffect(() => {
    const savedEndpoint = localStorage.getItem('casEndpoint');
    if (savedEndpoint) {
      setFormData(prev => ({
        ...prev,
        endpoint: savedEndpoint
      }));
    }
  }, []);

  const handleChange = (e) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value
    });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!formData.casToken || !formData.endpoint) {
      setError('Please fill in all fields');
      return;
    }

    setIsValidating(true);
    setError('');

    try {
      const response = await fetch(`${API_BASE_URL}/api/auth/validate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          cas_api_key: formData.casToken,
          cas_endpoint: formData.endpoint
        })
      });

      const data = await response.json();

      if (!response.ok) {
        // FastAPI validation errors (422) return { detail: [...] }
        // Our own error responses return { error: "..." }
        const detail = data.detail;
        if (Array.isArray(detail) && detail.length > 0) {
          throw new Error(detail.map(d => d.msg).join(', '));
        }
        throw new Error(data.error || data.detail || 'Validation failed');
      }

      if (data.valid) {
        localStorage.setItem('casEndpoint', formData.endpoint);

        const stores = data.vector_stores || [];
        const creds = {
          casToken: formData.casToken,
          endpoint: formData.endpoint,
          vectorStores: stores
        };

        if (stores.length > 0) {
          // Go to step 2 — let the user pick a vector store
          setPendingCreds(creds);
          setVectorStores(stores);
          setSelectedVectorStore(stores[0].id);
        } else {
          // No vector stores available — block login
          setError('No vector stores found on this CAS endpoint. Please contact your administrator.');
        }
      } else {
        setError(data.message || 'Invalid credentials');
      }
    } catch (err) {
      console.error('Validation error:', err);
      if (err.message === 'Failed to fetch') {
        setError('Could not connect to the backend. Please make sure the backend server is running.');
      } else {
        setError(err.message || 'Failed to validate credentials. Please check your token and endpoint.');
      }
    } finally {
      setIsValidating(false);
    }
  };

  const handleVectorStoreConfirm = () => {
    onLogin({ ...pendingCreds, selectedVectorStore });
  };

  const handleBackToLogin = () => {
    setVectorStores(null);
    setSelectedVectorStore('');
    setPendingCreds(null);
  };

  // ── Step 2: vector store picker ──────────────────────────────────────────
  if (vectorStores !== null) {
    return (
      <div className="modal-overlay" onClick={onClose}>
        <div className="modal-content" onClick={(e) => e.stopPropagation()}>
          <div className="modal-header">
            <div className="modal-header-left">
              {initialStep === 'credentials' && (
                <button className="back-button" onClick={handleBackToLogin} title="Back">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="15 18 9 12 15 6"/>
                  </svg>
                </button>
              )}
              <h2>Choose a Vector Store</h2>
            </div>
            <button className="close-button" onClick={onClose}>×</button>
          </div>

          <p className="vs-step-hint">
            Select the vector store you want to query against. You can change this after logging in.
          </p>

          <div className="vs-list">
            {vectorStores.map((store) => (
              <label
                key={store.id}
                className={`vs-option${selectedVectorStore === store.id ? ' vs-option--selected' : ''}`}
              >
                <input
                  type="radio"
                  name="vectorStore"
                  value={store.id}
                  checked={selectedVectorStore === store.id}
                  onChange={() => setSelectedVectorStore(store.id)}
                />
                <div className="vs-option-body">
                  <span className="vs-option-name">{store.name || store.id}</span>
                  <span className="vs-option-id">{store.id}</span>
                </div>
                {selectedVectorStore === store.id && (
                  <svg className="vs-check" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12"/>
                  </svg>
                )}
              </label>
            ))}
          </div>

          <button
            className="submit-button"
            onClick={handleVectorStoreConfirm}
            disabled={!selectedVectorStore}
          >
            Continue
          </button>
        </div>
      </div>
    );
  }

  // ── Step 1: credentials form ─────────────────────────────────────────────
  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>Login to CAS Assistant</h2>
          <button className="close-button" onClick={onClose}>×</button>
        </div>
        
        <form onSubmit={handleSubmit} className="login-form">
          <div className="form-group">
            <label htmlFor="casToken">CAS Token</label>
            <div className="password-input-wrapper">
              <input
                type={showPassword ? "text" : "password"}
                id="casToken"
                name="casToken"
                value={formData.casToken}
                onChange={handleChange}
                placeholder="Enter your CAS token"
                required
              />
              <button
                type="button"
                className="toggle-password"
                onClick={() => setShowPassword(!showPassword)}
                aria-label={showPassword ? "Hide password" : "Show password"}
              >
                {showPassword ? (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/>
                    <line x1="1" y1="1" x2="23" y2="23"/>
                  </svg>
                ) : (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
                    <circle cx="12" cy="12" r="3"/>
                  </svg>
                )}
              </button>
            </div>
            <small className="form-hint">Your CAS token will be used for authentication</small>
          </div>

          <div className="form-group">
            <label htmlFor="endpoint">Endpoint URL</label>
            <input
              type="text"
              id="endpoint"
              name="endpoint"
              value={formData.endpoint}
              onChange={handleChange}
              placeholder="https://api.example.com"
              required
            />
            <small className="form-hint">This URL will be saved locally for future sessions</small>
          </div>

          {error && (
            <div className="error-message">
              ⚠️ {error}
            </div>
          )}

          <button
            type="submit"
            className="submit-button"
            disabled={isValidating}
          >
            {isValidating ? 'Validating...' : 'Login'}
          </button>
        </form>
      </div>
    </div>
  );
}

export default LoginModal;