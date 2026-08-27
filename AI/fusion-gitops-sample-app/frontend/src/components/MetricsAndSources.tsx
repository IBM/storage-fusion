import type { SourceAttribution, ResponseMetrics } from '../types'
import { useState } from 'react'

interface Props {
  metrics?: ResponseMetrics
  sources?: SourceAttribution[]
}

export function MetricsAndSources({ metrics, sources }: Props) {
  const [open, setOpen] = useState(false)

  if (!metrics && (!sources || sources.length === 0)) return null

  return (
    <div className="mt-3">
      {/* Metric cards */}
      {metrics && (
        <div className="flex gap-2.5 mb-3">
          <div className="metric-card">
            <div className="text-[1.25rem] font-bold text-[#7EB3FA] leading-tight">
              {metrics.processing_time.toFixed(2)}s
            </div>
            <div className="text-[0.70rem] text-muted uppercase tracking-[0.06em] mt-0.5">
              Processing Time
            </div>
          </div>
          <div className="metric-card">
            <div className="text-[1.25rem] font-bold text-[#7EB3FA] leading-tight">
              {metrics.sources_count}
            </div>
            <div className="text-[0.70rem] text-muted uppercase tracking-[0.06em] mt-0.5">
              Sources Used
            </div>
          </div>
          <div className="metric-card">
            <div className="text-[1.25rem] font-bold text-[#7EB3FA] leading-tight">
              {metrics.cas_search_count}
            </div>
            <div className="text-[0.70rem] text-muted uppercase tracking-[0.06em] mt-0.5">
              CAS Passes
            </div>
          </div>
        </div>
      )}

      {/* Sources expander */}
      {sources && sources.length > 0 ? (
        <div className="bg-surface-3 border border-white/[0.07] rounded-[10px] overflow-hidden">
          <button
            onClick={() => setOpen((v) => !v)}
            className="w-full flex items-center justify-between px-4 py-2.5 text-sm font-semibold text-secondary hover:text-primary transition-colors"
          >
            <span>
              View {sources.length} cited source{sources.length !== 1 ? 's' : ''}
            </span>
            <span className="text-muted text-xs ml-2">{open ? '▲' : '▼'}</span>
          </button>

          {open && (
            <div className="px-4 pb-4 space-y-3">
              {sources.map((s, i) => {
                const linesStr =
                  s.line_start && s.line_end
                    ? `Lines ${s.line_start}–${s.line_end} · `
                    : ''
                return (
                  <div key={i} className="source-card">
                    <div className="text-sm font-semibold text-primary mb-1">
                      Source {i + 1} — {s.source_file}
                    </div>
                    <div className="text-[0.75rem] text-muted mb-2">
                      {linesStr}Relevance: {s.relevance_score.toFixed(4)} · ID:{' '}
                      <code className="text-[0.72rem] bg-surface-4 px-1 rounded">
                        {s.document_id}
                      </code>
                    </div>
                    {s.content_snippet && (
                      <textarea
                        readOnly
                        value={s.content_snippet}
                        rows={3}
                        className="w-full bg-surface-4 border border-white/[0.06] text-subtle text-xs rounded-lg px-3 py-2 resize-none outline-none font-mono"
                      />
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </div>
      ) : (
        <p className="text-xs text-muted italic">
          No sources found in CAS for this query. Response is based on general LLM knowledge.
        </p>
      )}
    </div>
  )
}
