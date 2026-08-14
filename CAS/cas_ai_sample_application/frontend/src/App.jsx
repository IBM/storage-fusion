import React, { useState, useEffect, useRef } from 'react';
import './App.css';
import LoginModal from './components/LoginModal.jsx';
import ChatInterface from './components/ChatInterface.jsx';
import { API_BASE_URL } from './config';
import ibmLogo from './assets/01_8-bar-positive.png';
import ibmLogoDark from './assets/download.png';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [showLoginModal, setShowLoginModal] = useState(false);
  // When re-opening for store change, skip straight to step 2
  const [loginModalMode, setLoginModalMode] = useState('full'); // 'full' | 'change-store'
  const [credentials, setCredentials] = useState(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);
  // Ref to ChatInterface's handleNewChat — registered by the child on mount.
  const newChatFnRef = useRef(null);
  // null = not checked yet, '' = passed, '<model>' = failed with this model name
  const [llmWarning, setLlmWarning] = useState(null);
  // Session handling toggle — persisted in localStorage, synced with backend at login
  const [sessionEnabled, setSessionEnabled] = useState(
    () => localStorage.getItem('sessionEnabled') !== 'false'
  );

  // Theme: initialise from localStorage, fallback to 'light'
  const [theme, setTheme] = useState(() => localStorage.getItem('theme') || 'light');

  // Apply data-theme to <html> whenever theme changes
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }, [theme]);

  const toggleTheme = () => setTheme((t) => (t === 'light' ? 'dark' : 'light'));

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
      .then(data => { setLlmWarning(data.compatible ? '' : data.model); })
      .catch(() => { setLlmWarning(''); });
    // Sync the backend session state to match whatever the user last chose.
    // We read from localStorage (the user's preference) and push it to the
    // backend — not the other way around — so toggling is preserved across
    // page refreshes and logins.
    const stored = localStorage.getItem('sessionEnabled');
    const wantEnabled = stored !== 'false'; // default true if never set
    fetch(`${API_BASE_URL}/api/session/status`)
      .then(r => r.json())
      .then(data => {
        if (data.enabled !== wantEnabled) {
          // Backend disagrees with stored preference — flip it.
          return fetch(`${API_BASE_URL}/api/session/toggle`, { method: 'POST' });
        }
      })
      .catch(() => {/* best-effort — ignore network errors */});
  };

  const handleSessionToggle = () => {
    fetch(`${API_BASE_URL}/api/session/toggle`, { method: 'POST' })
      .then(r => r.json())
      .then(data => {
        setSessionEnabled(data.enabled);
        localStorage.setItem('sessionEnabled', data.enabled);
      })
      .catch(() => {/* ignore network errors — UI stays as-is */});
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
            src={theme === 'dark' ? ibmLogoDark : ibmLogo}
            alt="IBM"
            className={`ibm-logo${theme === 'dark' ? ' ibm-logo--dark' : ''}`}
          />
          <h1 className="app-title">CAS AI Sample Application</h1>
        </div>
        <div className="header-right">
          {/* Theme toggle */}
          <button
            className="theme-toggle"
            onClick={toggleTheme}
            title={theme === 'light' ? 'Switch to dark mode' : 'Switch to light mode'}
            aria-label={theme === 'light' ? 'Switch to dark mode' : 'Switch to light mode'}
          >
            {theme === 'light' ? (
              /* Moon icon — click to go dark */
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
              </svg>
            ) : (
              /* Sun icon — click to go light */
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="5"/>
                <line x1="12" y1="1" x2="12" y2="3"/>
                <line x1="12" y1="21" x2="12" y2="23"/>
                <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/>
                <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>
                <line x1="1" y1="12" x2="3" y2="12"/>
                <line x1="21" y1="12" x2="23" y2="12"/>
                <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/>
                <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>
              </svg>
            )}
          </button>

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
                  <button
                    className="vs-dropdown-item"
                    role="menuitem"
                    onClick={() => { newChatFnRef.current?.(); setMenuOpen(false); }}
                  >
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M12 5v14M5 12h14"/>
                    </svg>
                    New Chat
                  </button>
                  <div className="vs-dropdown-divider" />
                  <button
                    className="vs-dropdown-item vs-dropdown-item--toggle"
                    role="menuitem"
                    onClick={handleSessionToggle}
                  >
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M12 2a10 10 0 1 0 0 20A10 10 0 0 0 12 2z"/>
                      <path d="M12 6v6l4 2"/>
                    </svg>
                    <span className="vs-dropdown-toggle-label">Session History</span>
                    <span className={`session-toggle${sessionEnabled ? ' session-toggle--on' : ''}`} aria-hidden="true">
                      <span className="session-toggle-thumb" />
                    </span>
                  </button>
                  <div className="vs-dropdown-divider" />
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
          <ChatInterface
            credentials={credentials}
            llmWarning={llmWarning}
            theme={theme}
            sessionEnabled={sessionEnabled}
            onRegisterNewChat={(fn) => { newChatFnRef.current = fn; }}
          />
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
