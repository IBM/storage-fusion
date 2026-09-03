import type { ModelInfo } from '../types'
import { Select } from './Select'

interface Props {
  isReady: boolean

  // Unified model controls
  models: ModelInfo[]
  selectedModelId: string
  onModelChange: (id: string) => void
  autoDetect: boolean
  onAutoDetectChange: (on: boolean) => void

  // Vector store
  vectorStores: { id: string; name: string }[]
  selectedStoreId: string
  onStoreChange: (id: string) => void

  // Common
  hasMessages: boolean
  onNewChat: () => void
}

export function Sidebar({
  isReady,
  models,
  selectedModelId,
  onModelChange,
  autoDetect,
  onAutoDetectChange,
  vectorStores,
  selectedStoreId,
  onStoreChange,
  hasMessages,
  onNewChat,
}: Props) {
  const statusColor = isReady ? '#34D399' : '#FBBF24'
  const statusLabel = isReady ? 'Connected' : 'Not connected'

  const storeOptions = vectorStores.map((s) => ({ value: s.id, label: s.name || s.id }))
  const modelOptions = models.map((m) => ({ value: m.id, label: m.id }))

  return (
    <aside
      className="w-64 flex-shrink-0 flex flex-col border-r border-white/[0.07] px-4 py-4 overflow-y-auto"
      style={{ background: '#111620', minHeight: '100vh' }}
    >
      {/* Brand header */}
      <div className="flex items-center gap-2.5 pb-4 mb-4 border-b border-white/[0.07]">
        <div
          className="w-9 h-9 rounded-[9px] flex items-center justify-center text-base flex-shrink-0"
          style={{ background: 'linear-gradient(135deg, #2D6BE4 0%, #4F8EF7 100%)' }}
        >
          ❇
        </div>
        <div>
          <div className="text-[1.05rem] font-bold text-primary leading-tight">
            Agentic Chat Assistant
          </div>
          <div className="text-[0.72rem] mt-0.5" style={{ color: statusColor }}>
            ● {statusLabel}
          </div>
        </div>
      </div>

      {/* Auto Detect toggle */}
      <div className="mb-4">
        <div className="text-[0.68rem] text-muted uppercase tracking-[0.08em] mb-2">Auto Detect</div>
        <button
          onClick={() => onAutoDetectChange(!autoDetect)}
          className="w-full flex items-center justify-between px-3 py-2 rounded-lg border transition-colors"
          style={{
            background: autoDetect ? 'rgba(45,107,228,0.15)' : 'rgba(255,255,255,0.03)',
            borderColor: autoDetect ? 'rgba(45,107,228,0.5)' : 'rgba(255,255,255,0.08)',
          }}
        >
          <span className="text-[0.78rem] text-primary">
            Auto Detect
          </span>
          {/* Toggle pill */}
          <span
            className="relative inline-flex h-5 w-9 items-center rounded-full transition-colors flex-shrink-0"
            style={{ background: autoDetect ? '#2D6BE4' : 'rgba(255,255,255,0.12)' }}
          >
            <span
              className="inline-block h-3.5 w-3.5 rounded-full bg-white shadow transition-transform"
              style={{ transform: autoDetect ? 'translateX(18px)' : 'translateX(3px)' }}
            />
          </span>
        </button>
        <p className="text-[0.70rem] text-muted mt-1.5 leading-snug">
          {autoDetect
            ? 'Best model selected automatically based on your request.'
            : 'You choose the model below.'}
        </p>
      </div>

      {/* Model selector */}
      <div className="mb-4">
        {autoDetect ? (
          <>
            <div className="text-[0.68rem] text-muted uppercase tracking-[0.08em] mb-1">Model</div>
            <div
              className="w-full px-3 py-2 rounded-lg border text-[0.78rem] text-muted italic"
              style={{
                background: 'rgba(255,255,255,0.02)',
                borderColor: 'rgba(255,255,255,0.06)',
              }}
            >
              Automatically selected
            </div>
          </>
        ) : (
          <Select
            label="Model"
            value={selectedModelId}
            onChange={onModelChange}
            options={modelOptions}
            disabled={modelOptions.length === 0}
          />
        )}
        {!autoDetect && modelOptions.length === 0 && (
          <p className="text-[0.75rem] text-muted mt-1">No models available.</p>
        )}
      </div>

      {/* Vector Store */}
      <div className="mb-4">
        <Select
          label="CAS Vector Store"
          value={selectedStoreId}
          onChange={onStoreChange}
          options={storeOptions}
          disabled={storeOptions.length === 0}
        />
        {storeOptions.length === 0 && (
          <p className="text-[0.75rem] text-muted mt-1">No vector stores available.</p>
        )}
      </div>

      {/* New Chat */}
      <div className="mt-2">
        <button className="btn-secondary" onClick={onNewChat} disabled={!hasMessages}>
          New Chat
        </button>
      </div>

      <div className="flex-1" />
      <div className="text-[0.68rem] text-muted text-center pt-4 border-t border-white/[0.05] mt-4">
        Powered by IBM Fusion AI
      </div>
    </aside>
  )
}
