import React, { useState, useRef, useEffect } from 'react';
import ReactMarkdown from 'react-markdown';
import './ChatInterface.css';
import { API_BASE_URL, DEFAULT_MAX_RESULTS, DEFAULT_MIN_SCORE } from '../config';
import ibmLogo from '../assets/01_8-bar-positive.png';
import ibmLogoDark from '../assets/download.png';

function ChatInterface({ credentials, llmWarning, theme, sessionEnabled, onRegisterNewChat }) {
  const [messages, setMessages] = useState([]);
  const [inputValue, setInputValue] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [activeMessageId, setActiveMessageId] = useState(null);
  const [bannerDismissed, setBannerDismissed] = useState(false);
  const messagesEndRef = useRef(null);
  const abortControllerRef = useRef(null);
  // Session id returned by the backend in the [DONE] payload and forwarded on
  // every subsequent request so the backend can rewrite follow-up questions
  // against prior conversation history.  Null means no active session (first
  // message of a new chat, or history has been disabled).
  const sessionIdRef = useRef(null);
  // Tracks whether a stop is in-flight. Set to true the moment the stop button
  // is clicked and cleared only after the abort has fully settled and React has
  // re-rendered. This prevents the Enter key from firing a new submission in the
  // gap between abort() being called and isLoading flipping back to false.
  const isStoppingRef = useRef(false);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const handleNewChat = () => {
    if (isLoading) return;
    // Fire-and-forget: sweep the old session from the backend store immediately
    // so it doesn't linger until the TTL background sweep picks it up.
    if (sessionIdRef.current) {
      fetch(`${API_BASE_URL}/api/session/${sessionIdRef.current}`, { method: 'DELETE' })
        .catch(() => {/* best-effort — ignore network errors */});
    }
    sessionIdRef.current = null;
    setMessages([]);
    setInputValue('');
  };

  // Register handleNewChat with the parent (App.jsx) so it can be called
  // from the header dropdown without threading state back up.
  useEffect(() => {
    onRegisterNewChat?.(handleNewChat);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!inputValue.trim() || isLoading || isStoppingRef.current) return;

    const userMessage = {
      id: Date.now(),
      text: inputValue,
      sender: 'user',
      timestamp: new Date().toISOString()
    };

    setMessages(prev => [...prev, userMessage]);
    setInputValue('');
    setIsLoading(true);

    const endpoint = localStorage.getItem('casEndpoint') || credentials.endpoint;
    const casToken = credentials.casToken;
    const botId = Date.now() + 1;

    abortControllerRef.current = new AbortController();

    // Add an empty bot message immediately — tokens will stream into it
    setActiveMessageId(botId);
    setMessages(prev => [...prev, {
      id: botId,
      text: '',
      sender: 'assistant',
      timestamp: new Date().toISOString(),
      metadata: {}
    }]);

    try {
      const response = await fetch(`${API_BASE_URL}/api/query/stream`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: abortControllerRef.current.signal,
        body: JSON.stringify({
          query: inputValue,
          cas_api_key: casToken,
          cas_endpoint: endpoint,
          max_results: DEFAULT_MAX_RESULTS,
          min_score: DEFAULT_MIN_SCORE,
          vector_store_id: credentials.selectedVectorStore || null,
          ...(sessionEnabled && sessionIdRef.current ? { session_id: sessionIdRef.current } : {}),
        })
      });

      if (!response.ok) {
        // Extract the detail message from FastAPI's error response body if available.
        // This surfaces specific messages such as missing LLM_MODEL or LLM_BASE_URL.
        let detail = `Backend returned HTTP ${response.status}. Check the server logs for details.`;
        try {
          const errBody = await response.json();
          if (errBody?.error) detail = errBody.error;
          else if (errBody?.detail) detail = errBody.detail;
        } catch (_) {}
        setMessages(prev => prev.map(msg =>
          msg.id === botId ? { ...msg, text: detail } : msg
        ));
        setIsLoading(false);
        setActiveMessageId(null);
        return;
      }

      // Helper: extract url= and model= values from a sentinel string.
      const parseSentinel = (s) => {
        const url = (s.match(/url=([^\s\]]+)/) || [])[1] || 'unknown';
        const model = (s.match(/model=([^\s\]]+)/) || [])[1] || 'unknown';
        return { url, model };
      };

      // Read the stream token by token and append to the bot message live
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let accumulated = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        accumulated += chunk;

        // [THINKING] is a sentinel yielded by the backend before any content.
        // While it's present (and nothing else), keep showing the typing dots.
        const isThinking = accumulated === '[THINKING]';
        if (isThinking) continue;

        // [LLM_UNAVAILABLE ...] — connection refused or timeout.
        if (accumulated.includes('[LLM_UNAVAILABLE')) {
          const { url } = parseSentinel(accumulated);
          setMessages(prev => prev.map(msg =>
            msg.id === botId
              ? { ...msg, text: `Could not connect to the LLM backend at \`${url}\`.\n\nVerify the port-forward is running (or update LLM_BASE_URL in your .env if the URL is incorrect).` }
              : msg
          ));
          setIsLoading(false);
          setActiveMessageId(null);
          return;
        }

        // [LLM_NOT_FOUND ...] — Ollama is running but the model name is wrong.
        if (accumulated.includes('[LLM_NOT_FOUND')) {
          const { url, model } = parseSentinel(accumulated);
          setMessages(prev => prev.map(msg =>
            msg.id === botId
              ? { ...msg, text: `LLM_MODEL \`${model}\` was not found at \`${url}\`.\n\nUpdate LLM_MODEL in your .env file.` }
              : msg
          ));
          setIsLoading(false);
          setActiveMessageId(null);
          return;
        }

        // [LLM_HTTP_ERROR ...] — LLM returned an unexpected HTTP error status.
        if (accumulated.includes('[LLM_HTTP_ERROR')) {
          const { url, model } = parseSentinel(accumulated);
          const statusMatch = accumulated.match(/status=([^\s\]]+)/);
          const httpStatus = statusMatch ? statusMatch[1] : 'unknown';
          setMessages(prev => prev.map(msg =>
            msg.id === botId
              ? { ...msg, text: `LLM request failed (HTTP ${httpStatus}).\n\nLLM_BASE_URL: \`${url}\`\n\nLLM_MODEL: \`${model}\`\n\nCheck the backend logs for details.` }
              : msg
          ));
          setIsLoading(false);
          setActiveMessageId(null);
          return;
        }

        // Strip the [THINKING] sentinel from display text
        const withoutThinking = accumulated.replace('[THINKING]', '');

        // Check if the stream ended with a [DONE] metadata line
        const doneIdx = withoutThinking.lastIndexOf('\n[DONE]');
        let displayText = withoutThinking;
        let metadata = {};

        if (doneIdx !== -1) {
          displayText = withoutThinking.slice(0, doneIdx);
          const metadataStr = withoutThinking.slice(doneIdx + 7);
          try {
            metadata = JSON.parse(metadataStr);
            // Persist the session id for the next request in this conversation.
            if (metadata.session_id) {
              sessionIdRef.current = metadata.session_id;
            }
          } catch {
            // Malformed metadata — continue with empty object
          }
        }

        // Extract inline [SOURCE]{...} markers emitted per question.
        // Replace each marker with a "Source: <name>" line.
        const perQuestionSourceRegex = /\n\[SOURCE\](\{[^}]*\})/g;
        displayText = displayText.replace(perQuestionSourceRegex, (_, jsonStr) => {
          try {
            const { source_name } = JSON.parse(jsonStr);
            return source_name ? `\n\nSource: ${source_name}` : '';
          } catch {
            return '';
          }
        });

        // Strip structured-output boilerplate the model may emit.
        // Handles single-question (one FULL_ANSWER: block) and multi-question
        // (multiple blocks separated by --- dividers) equally.
        // Also handles gemma4's habit of wrapping field names in **bold**.
        const renderedText = displayText
          // Remove CORE_ANSWER: lines (plain or **bold**)
          .replace(/^\*{0,2}CORE_ANSWER:\*{0,2}.*$/gim, '')
          // Replace "FULL_ANSWER: <text>" (plain or **bold**) up to a [SOURCE line
          .replace(/\*{0,2}FULL_ANSWER:\*{0,2}\s*([\s\S]*?)(?=\n\*{0,2}[[(]SOURCE:|\n\*{0,2}\(SOURCE\s+\d|$)/gi, '$1')
          // Remove citation tags: [SOURCE: N], [SOURCE: N/A], (SOURCE N), **[SOURCE: N]**
          // Uses full bracket pairs so nothing leaks out. Preceded by optional whitespace/comma.
          .replace(/[,\s]*\*{0,2}\[SOURCE:\s*(?:\d+|N\/A|user-context)\]\*{0,2}/gi, '')
          .replace(/[,\s]*\*{0,2}\(SOURCE\s+(?:\d+|N\/A)\)\*{0,2}/gi, '')
          // Bare "SOURCE: N", "SOURCE: N/A", or "SOURCE: user-context" not inside brackets
          .replace(/^\*{0,2}SOURCE:\s*(?:\d+|N\/A|user-context)\*{0,2}$/gim, '')
          // Collapse 3+ consecutive newlines into 2
          .replace(/\n{3,}/g, '\n\n')
          .trim();

        // Update the bot message in place as tokens arrive
        setMessages(prev => prev.map(msg =>
          msg.id === botId
            ? { ...msg, text: renderedText, metadata }
            : msg
        ));
      }

      setIsLoading(false);
      setActiveMessageId(null);
    } catch (error) {
      if (error.name !== 'AbortError') {
        setMessages(prev => prev.map(msg =>
          msg.id === botId
            ? { ...msg, text: 'Sorry, there was an error processing your request. Please try again.' }
            : msg
        ));
      }
      setIsLoading(false);
      setActiveMessageId(null);
      // Abort has fully settled — clear the stopping guard after React re-renders
      // so the send button is visible before a new submission can be triggered.
      setTimeout(() => { isStoppingRef.current = false; }, 0);
    }
  };

  const handleStop = () => {
    if (abortControllerRef.current) {
      isStoppingRef.current = true;
      abortControllerRef.current.abort();
    }
  };

  // onKeyDown replaces the deprecated onKeyPress event handler.
  // The behaviour is identical for Enter detection but onKeyDown is the
  // current W3C standard and avoids React deprecation warnings.
  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (!isLoading && !isStoppingRef.current) handleSubmit(e);
    }
  };

  const copyToClipboard = (text) => {
    navigator.clipboard.writeText(text).catch(err => {
      console.error('Failed to copy:', err);
    });
  };

  return (
    <div className="chat-interface">
      <div className="messages-container">
        {messages.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">💬</div>
            <h3>Start a conversation</h3>
            <p>Ask me anything about IBM Fusion Content Aware Storage</p>
          </div>
        ) : (
          <div className="messages-list">
            {messages.map((message) => (
              <div key={message.id} className={`message ${message.sender}`}>
                {message.sender === 'assistant' && (
                  <div className="message-avatar">
                    <img
                      src={theme === 'dark' ? ibmLogoDark : ibmLogo}
                      alt="IBM"
                      className={`bot-avatar-image${theme === 'dark' ? ' bot-avatar-image--dark' : ''}`}
                    />
                  </div>
                )}
                <div className="message-content">
                  {message.sender === 'assistant' && (
                    <div className="message-header">
                      <span className="message-sender-name">CAS AI Sample Application</span>
                      <button
                        className="copy-button"
                        onClick={() => copyToClipboard(message.text)}
                        title="Copy answer"
                      >
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                          <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
                        </svg>
                      </button>
                    </div>
                  )}
                  {message.sender === 'assistant' && message.id === activeMessageId && !message.text ? (
                    <div className="typing-indicator">
                      <span></span>
                      <span></span>
                      <span></span>
                    </div>
                  ) : message.sender === 'assistant' ? (
                    <div className="message-text markdown-body">
                      <ReactMarkdown
                        components={{
                          p({ children }) {
                            const text = Array.isArray(children) ? children.join('') : String(children ?? '');
                            if (text.startsWith('Source: ')) {
                              return <p className="source-line">{children}</p>;
                            }
                            return <p>{children}</p>;
                          }
                        }}
                      >{message.text}</ReactMarkdown>
                      {message.id === activeMessageId && (
                        <div className="generating-indicator">
                          <span className="generating-dot"></span>
                          <span className="generating-label">Generating...</span>
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="message-text" style={{ whiteSpace: 'pre-wrap' }}>
                      {message.text}
                    </div>
                  )}
                  {message.sender === 'assistant' && message.metadata?.model && (
                    <div className="model-badge">{message.metadata.model}</div>
                  )}
                </div>
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      <div className="input-container">
        {llmWarning && !bannerDismissed && (
          <div className="llm-warning-banner">
            <span className="llm-warning-text">
              ⚠ <strong>{llmWarning}</strong> may not return reliable answers.
              Consider a 7B+ model (e.g. <code>llama3.1:8b</code>) for better results.
            </span>
            <button
              className="llm-warning-dismiss"
              onClick={() => setBannerDismissed(true)}
              aria-label="Dismiss warning"
              title="Dismiss"
            >×</button>
          </div>
        )}
        <div className="input-row">
          <form onSubmit={handleSubmit} className="input-form">
          <textarea
            value={inputValue}
            onChange={(e) => setInputValue(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask about CAS features, configuration, or best practices..."
            className="message-input"
            rows="1"
          />
          {isLoading ? (
            <button
              type="button"
              className="stop-button"
              onClick={handleStop}
              title="Stop generating"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                <rect x="4" y="4" width="16" height="16" rx="2"/>
              </svg>
            </button>
          ) : (
            <button
              type="submit"
              className="send-button"
              disabled={!inputValue.trim()}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
                <path d="M22 2L11 13" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                <path d="M22 2L15 22L11 13L2 9L22 2Z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </button>
          )}
          </form>
        </div>
      </div>
    </div>
  );
}

export default ChatInterface;
