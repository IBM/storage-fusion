import React, { useState, useRef, useEffect } from 'react';
import './McpPanel.css';

/**
 * McpPanel — popup panel anchored above the + button beside the search bar.
 *
 * Layout (top → bottom inside the panel):
 *   1. Header ("MCP Connections" + close ×)
 *   2. Add-server form (always visible at the top)
 *   3. Divider
 *   4. Saved connections list with per-item toggle + delete
 *
 * Props:
 *   connections  — array of { id, name, url, authToken, enabled }
 *   onChange(connections) — called with the full updated array on every change
 *   onClose()   — called when the panel should close
 */
function McpPanel({ connections, onChange, onClose }) {
  const [name, setName]           = useState('');
  const [url, setUrl]             = useState('');
  const [authToken, setAuthToken] = useState('');
  const [error, setError]         = useState('');
  const [added, setAdded]         = useState(false); // brief success flash
  const panelRef    = useRef(null);
  const nameInputRef = useRef(null);

  // Auto-focus the name field when the panel opens.
  useEffect(() => { nameInputRef.current?.focus(); }, []);

  // Close on Escape.
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  // Close on click outside — delay by one tick so the opening click doesn't
  // immediately re-trigger this listener.
  useEffect(() => {
    const handler = (e) => {
      if (panelRef.current && !panelRef.current.contains(e.target)) onClose();
    };
    const t = setTimeout(() => document.addEventListener('mousedown', handler), 0);
    return () => { clearTimeout(t); document.removeEventListener('mousedown', handler); };
  }, [onClose]);

  const resetForm = () => { setName(''); setUrl(''); setAuthToken(''); setError(''); };

  const handleAdd = (e) => {
    e.preventDefault();
    setError('');
    const n = name.trim();
    const u = url.trim();
    const t = authToken.trim();

    if (!n) { setError('Name is required.'); return; }
    if (!u) { setError('Endpoint URL is required.'); return; }
    if (!t) { setError('Auth token is required.'); return; }
    if (!/^https?:\/\/.+/.test(u)) { setError('URL must start with http:// or https://'); return; }
    if (connections.some(c => c.name === n)) {
      setError(`"${n}" already exists. Choose a different name.`);
      return;
    }

    const next = [
      ...connections,
      { id: Date.now(), name: n, url: u, authToken: t, enabled: true },
    ];
    onChange(next);
    resetForm();
    setAdded(true);
    setTimeout(() => setAdded(false), 1800);
  };

  const toggleEnabled = (id) =>
    onChange(connections.map(c => c.id === id ? { ...c, enabled: !c.enabled } : c));

  const remove = (id) => onChange(connections.filter(c => c.id !== id));

  return (
    <div className="mcp-panel" ref={panelRef} role="dialog" aria-label="MCP Connections">

      {/* ── Header ───────────────────────────────────────────────── */}
      <div className="mcp-panel-header">
        <div className="mcp-panel-header-left">
          {/* Chain-link icon */}
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="mcp-panel-icon">
            <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
            <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
          </svg>
          <span className="mcp-panel-title">MCP Connections</span>
        </div>
        <button className="mcp-panel-close" onClick={onClose} aria-label="Close panel">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>

      {/* ── Add-server form (always at the top) ──────────────────── */}
      <form className="mcp-add-form" onSubmit={handleAdd} noValidate>
        <p className="mcp-add-heading">Add MCP server</p>

        {error && (
          <p className="mcp-add-error" role="alert">{error}</p>
        )}
        {added && !error && (
          <p className="mcp-add-success" role="status">✓ Connection saved</p>
        )}

        <div className="mcp-field-row">
          <label className="mcp-field-label" htmlFor="mcp-name">Name</label>
          <input
            id="mcp-name"
            ref={nameInputRef}
            className="mcp-field-input"
            type="text"
            value={name}
            onChange={e => { setError(''); setName(e.target.value); }}
            placeholder="my-mcp-server"
            autoComplete="off"
            maxLength={100}
          />
        </div>

        <div className="mcp-field-row">
          <label className="mcp-field-label" htmlFor="mcp-url">Endpoint URL</label>
          <input
            id="mcp-url"
            className="mcp-field-input"
            type="url"
            value={url}
            onChange={e => { setError(''); setUrl(e.target.value); }}
            placeholder="https://…/cas/api/v1/mcp-streamable/"
            autoComplete="off"
            maxLength={500}
          />
        </div>

        <div className="mcp-field-row">
          <label className="mcp-field-label" htmlFor="mcp-token">Auth Token</label>
          <input
            id="mcp-token"
            className="mcp-field-input"
            type="password"
            value={authToken}
            onChange={e => { setError(''); setAuthToken(e.target.value); }}
            placeholder="Bearer / API token"
            autoComplete="new-password"
            maxLength={500}
          />
        </div>

        <div className="mcp-add-actions">
          <button
            type="button"
            className="mcp-cancel-btn"
            onClick={resetForm}
            tabIndex={name || url || authToken ? 0 : -1}
            style={{ visibility: name || url || authToken ? 'visible' : 'hidden' }}
          >
            Clear
          </button>
          <button type="submit" className="mcp-add-btn">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
              <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
            </svg>
            Add
          </button>
        </div>
      </form>

      {/* ── Saved connections ─────────────────────────────────────── */}
      {connections.length > 0 && (
        <>
          <div className="mcp-section-divider">
            <span className="mcp-section-label">Saved ({connections.length})</span>
          </div>
          <ul className="mcp-connection-list">
            {connections.map(conn => (
              <li
                key={conn.id}
                className={`mcp-connection-item${conn.enabled ? ' mcp-connection-item--on' : ''}`}
              >
                <div className="mcp-connection-info">
                  <span className="mcp-connection-name">{conn.name}</span>
                  <span className="mcp-connection-url" title={conn.url}>{conn.url}</span>
                </div>
                <div className="mcp-connection-actions">
                  {/* Toggle on/off */}
                  <button
                    type="button"
                    className="mcp-toggle-btn"
                    onClick={() => toggleEnabled(conn.id)}
                    title={conn.enabled ? 'Disable' : 'Enable'}
                    aria-label={conn.enabled ? `Disable ${conn.name}` : `Enable ${conn.name}`}
                  >
                    <span className={`mcp-toggle${conn.enabled ? ' mcp-toggle--on' : ''}`} aria-hidden="true">
                      <span className="mcp-toggle-thumb" />
                    </span>
                  </button>
                  {/* Delete */}
                  <button
                    type="button"
                    className="mcp-remove-btn"
                    onClick={() => remove(conn.id)}
                    title={`Remove ${conn.name}`}
                    aria-label={`Remove ${conn.name}`}
                  >
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <polyline points="3 6 5 6 21 6"/>
                      <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>
                      <path d="M10 11v6M14 11v6"/>
                      <path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>
                    </svg>
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </>
      )}

      {connections.length === 0 && (
        <p className="mcp-empty-hint">
          CAS is always queried by default. Add extra MCP servers above to include them in every search.
        </p>
      )}
    </div>
  );
}

export default McpPanel;
