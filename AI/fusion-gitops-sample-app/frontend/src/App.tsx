import { useState, useEffect, useRef, useCallback } from 'react'
import type { Message, ModelInfo, HistoryMessage } from './types'
import { api } from './api'
import { Sidebar } from './components/Sidebar'
import { ChatMessage } from './components/ChatMessage'
import { WelcomeScreen } from './components/WelcomeScreen'

let _msgCounter = 0
function uid() {
  return String(++_msgCounter)
}

export default function App() {
  // ── Chat state ────────────────────────────────────────────────────────────
  const [messages, setMessages] = useState<Message[]>([])
  const [inputValue, setInputValue] = useState('')
  const [isProcessing, setIsProcessing] = useState(false)
  const bottomRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)

  // ── Model / store state ───────────────────────────────────────────────────
  const [models, setModels] = useState<ModelInfo[]>([])
  const [selectedModelId, setSelectedModelId] = useState('')   // empty = use default
  const [autoDetect, setAutoDetect] = useState(false)          // OFF by default
  const [vectorStores, setVectorStores] = useState<{ id: string; name: string }[]>([])
  const [selectedStoreId, setSelectedStoreId] = useState('')

  // ── Init status ───────────────────────────────────────────────────────────
  const [isReady, setIsReady] = useState(false)
  const [initError, setInitError] = useState<string | null>(null)

  /* ── Bootstrap: load models + vector stores ───────────────────────────── */
  useEffect(() => {
    async function init() {
      try {
        const [modelList, stores] = await Promise.all([
          api.getModels(),
          api.getVectorStores(),
        ])
        setModels(modelList)
        setVectorStores(stores)

        // Select the default model (marked by the backend)
        const defaultModel = modelList.find((m) => m.default) ?? modelList[0]
        if (defaultModel) setSelectedModelId(defaultModel.id)

        // Select first available vector store
        if (stores.length > 0) setSelectedStoreId(stores[0].id)

        if (modelList.length > 0) setIsReady(true)
      } catch (err) {
        setInitError(err instanceof Error ? err.message : String(err))
      }
    }
    init()
  }, [])

  /* ── Auto-scroll on new messages ─────────────────────────────────────────*/
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, isProcessing])

  /* ── Send message ────────────────────────────────────────────────────────*/
  const sendMessage = useCallback(async (promptOverride?: string) => {
    const query = (promptOverride ?? inputValue).trim()
    if (!query || isProcessing) return

    setInputValue('')
    setIsProcessing(true)
    setMessages((prev) => [...prev, { id: uid(), role: 'user', content: query }])

    if (!isReady) {
      setMessages((prev) => [
        ...prev,
        {
          id: uid(),
          role: 'assistant',
          content: 'Service is not yet connected. Please wait for initialisation or refresh the page.',
          error: true,
        },
      ])
      setIsProcessing(false)
      return
    }

    // Build conversation history from previous messages
    const history: HistoryMessage[] = messages
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .map((m) => ({ role: m.role, content: m.content }))

    try {
      const result = await api.chat({
        query,
        vector_store_id: selectedStoreId,
        model_id: autoDetect ? '' : selectedModelId,
        auto_detect: autoDetect,
        max_tokens: 512,
        temperature: 0.7,
        history,
      })

      setMessages((prev) => [
        ...prev,
        {
          id: uid(),
          role: 'assistant',
          content: result.response,
          modelId: result.model_id,
          sources: result.sources,
          metrics: result.metrics ?? undefined,
          usage: result.usage ?? undefined,
        },
      ])
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        {
          id: uid(),
          role: 'assistant',
          content: `Something went wrong: ${err instanceof Error ? err.message : String(err)}`,
          error: true,
        },
      ])
    } finally {
      setIsProcessing(false)
    }
  }, [inputValue, isProcessing, isReady, selectedModelId, selectedStoreId, autoDetect, messages])

  /* ── Keyboard handler ────────────────────────────────────────────────── */
  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
  }

  /* ── Auto-resize textarea ────────────────────────────────────────────── */
  const handleInput = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInputValue(e.target.value)
    const el = e.target
    el.style.height = 'auto'
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`
  }

  return (
    <div className="flex h-screen overflow-hidden">
      {/* Sidebar */}
      <Sidebar
        isReady={isReady}
        models={models}
        selectedModelId={selectedModelId}
        onModelChange={setSelectedModelId}
        autoDetect={autoDetect}
        onAutoDetectChange={setAutoDetect}
        vectorStores={vectorStores}
        selectedStoreId={selectedStoreId}
        onStoreChange={setSelectedStoreId}
        hasMessages={messages.length > 0}
        onNewChat={() => setMessages([])}
      />

      {/* Main area */}
      <main className="flex flex-col flex-1 overflow-hidden">
        {/* Init error banner */}
        {initError && (
          <div className="bg-red-950/60 border-b border-red-800/40 text-red-300 text-xs px-5 py-2">
            ⚠ Failed to connect to backend: {initError}
          </div>
        )}

        {/* Chat messages */}
        <div className="flex-1 overflow-y-auto px-6 pt-6 pb-36">
          {messages.length === 0 && !isProcessing ? (
            <WelcomeScreen
              onSuggestion={(prefill) => {
                setInputValue(prefill)
                setTimeout(() => {
                  const el = inputRef.current
                  if (!el) return
                  el.focus()
                  el.style.height = 'auto'
                  el.style.height = `${Math.min(el.scrollHeight, 160)}px`
                  el.setSelectionRange(prefill.length, prefill.length)
                }, 0)
              }}
            />
          ) : (
            <div className="max-w-3xl mx-auto">
              {messages.map((msg) => (
                <ChatMessage key={msg.id} message={msg} />
              ))}
              {isProcessing && (
                <div className="flex items-center gap-2 text-muted text-sm my-4">
                  <span className="inline-flex gap-1">
                    <span className="w-1.5 h-1.5 bg-brand rounded-full animate-bounce [animation-delay:-0.3s]" />
                    <span className="w-1.5 h-1.5 bg-brand rounded-full animate-bounce [animation-delay:-0.15s]" />
                    <span className="w-1.5 h-1.5 bg-brand rounded-full animate-bounce" />
                  </span>
                  <span>Thinking…</span>
                </div>
              )}
              <div ref={bottomRef} />
            </div>
          )}
        </div>

        {/* Chat input bar */}
        <div className="border-t border-white/[0.07] px-6 py-4" style={{ background: '#0D1117' }}>
          <div className="max-w-3xl mx-auto relative">
            <textarea
              ref={inputRef}
              value={inputValue}
              onChange={handleInput}
              onKeyDown={handleKeyDown}
              placeholder={
                autoDetect
                  ? 'Ask a question… model selected automatically (Shift+Enter for new line)'
                  : 'Ask a question… (Shift+Enter for new line)'
              }
              rows={1}
              disabled={isProcessing}
              className="w-full bg-[#161B26] border border-white/[0.08] text-primary text-sm rounded-xl px-4 py-3 pr-14 outline-none focus:border-brand/60 focus:ring-2 focus:ring-brand/10 resize-none overflow-hidden leading-relaxed placeholder:text-muted transition-all disabled:opacity-50"
              style={{ minHeight: '48px' }}
            />
            <button
              onClick={() => sendMessage()}
              disabled={!inputValue.trim() || isProcessing}
              className="absolute right-3 bottom-3 w-8 h-8 flex items-center justify-center rounded-lg transition-all disabled:opacity-30"
              style={{
                background:
                  inputValue.trim() && !isProcessing
                    ? 'linear-gradient(135deg, #2D6BE4 0%, #4F8EF7 100%)'
                    : 'rgba(255,255,255,0.06)',
              }}
              aria-label="Send"
            >
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path
                  d="M13 1L6.5 7.5M13 1L9 13L6.5 7.5M13 1L1 5L6.5 7.5"
                  stroke="white"
                  strokeWidth="1.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
            </button>
          </div>
          <p className="text-center text-[0.68rem] text-muted mt-2">
            Press Enter to send · Shift+Enter for a new line
          </p>
        </div>
      </main>
    </div>
  )
}
