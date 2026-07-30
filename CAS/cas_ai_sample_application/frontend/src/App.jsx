import React, { useState, useEffect, useRef } from 'react';
import './App.css';
import LoginModal from './components/LoginModal.jsx';
import ChatInterface from './components/ChatInterface.jsx';
import { API_BASE_URL } from './config';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [showLoginModal, setShowLoginModal] = useState(false);
  // When re-opening for store change, skip straight to step 2
  const [loginModalMode, setLoginModalMode] = useState('full'); // 'full' | 'change-store'
  const [credentials, setCredentials] = useState(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);
  // null = not checked yet, '' = passed, '<model>' = failed with this model name
  const [llmWarning, setLlmWarning] = useState(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        setMenuOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleLogin = (creds) => {
    setCredentials(creds);
    setIsAuthenticated(true);
    setShowLoginModal(false);
    setLoginModalMode('full');
    // Run the LLM format-compliance probe after login — non-blocking.
    fetch(`${API_BASE_URL}/api/llm/check`)
      .then(r => r.json())
      .then(data => {
        setLlmWarning(data.compatible ? '' : data.model);
      })
      .catch(() => {
        // If the check itself fails (backend down etc.) don't show a warning.
        setLlmWarning('');
      });
  };

  const handleLogout = () => {
    setIsAuthenticated(false);
    setCredentials(null);
    setMenuOpen(false);
    setLlmWarning(null);
  };

  const handleChangeStore = () => {
    setMenuOpen(false);
    setLoginModalMode('change-store');
    setShowLoginModal(true);
  };

  const currentStoreName = credentials?.selectedVectorStore || null;

  return (
    <div className="App">
      <header className="app-header">
        <div className="header-left">
          <img
            src="https://www.ibm.com/brand/experience-guides/developer/b1db1ae501d522a1a4b49613fe07c9f1/01_8-bar-positive.svg"
            alt="IBM Logo"
            className="ibm-logo"
          />
          <h1 className="app-title">CAS AI Sample Application</h1>
        </div>
        <div className="header-right">
          {isAuthenticated ? (
            <div className="vs-menu-wrapper" ref={menuRef}>
              <button
                className="vs-pill"
                onClick={() => setMenuOpen((o) => !o)}
                aria-haspopup="true"
                aria-expanded={menuOpen}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="vs-pill-icon">
                  <ellipse cx="12" cy="5" rx="9" ry="3"/>
                  <path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/>
                  <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>
                </svg>
                <span className="vs-pill-name">{currentStoreName || 'No store selected'}</span>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className={`vs-pill-chevron${menuOpen ? ' vs-pill-chevron--open' : ''}`}>
                  <polyline points="6 9 12 15 18 9"/>
                </svg>
              </button>

              {menuOpen && (
                <div className="vs-dropdown" role="menu">
                  <button className="vs-dropdown-item" role="menuitem" onClick={handleChangeStore}>
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <ellipse cx="12" cy="5" rx="9" ry="3"/>
                      <path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/>
                      <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>
                    </svg>
                    Change Vector Store
                  </button>
                  <div className="vs-dropdown-divider" />
                  <button className="vs-dropdown-item vs-dropdown-item--danger" role="menuitem" onClick={handleLogout}>
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>
                      <polyline points="16 17 21 12 16 7"/>
                      <line x1="21" y1="12" x2="9" y2="12"/>
                    </svg>
                    Logout
                  </button>
                </div>
              )}
            </div>
          ) : (
            <button className="login-button" onClick={() => setShowLoginModal(true)}>
              Login
            </button>
          )}
        </div>
      </header>

      <main className="app-main">
        {isAuthenticated ? (
          <ChatInterface credentials={credentials} llmWarning={llmWarning} />
        ) : (
          <div className="welcome-screen">
            <h2>Welcome to the CAS AI Sample Application</h2>
            <p>Please login to start chatting with the Content Aware Storage assistant.</p>
            <button className="welcome-login-button" onClick={() => setShowLoginModal(true)}>
              Get Started
            </button>
          </div>
        )}
      </main>

      {showLoginModal && (
        <LoginModal
          onClose={() => { setShowLoginModal(false); setLoginModalMode('full'); }}
          onLogin={handleLogin}
          initialStep={loginModalMode === 'change-store' ? 'vector-store' : 'credentials'}
          initialVectorStores={loginModalMode === 'change-store' ? credentials?.vectorStores : null}
          initialPendingCreds={loginModalMode === 'change-store' ? credentials : null}
        />
      )}
    </div>
  );
}

export default App;