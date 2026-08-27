interface Props {
  onSuggestion?: (prefill: string) => void
}

const SUGGESTIONS = [
  { label: 'Write a Python function',   prefill: 'Write a Python function that ' },
  { label: 'Find specific information', prefill: '' },
  { label: 'Extract key points',        prefill: 'Extract the key points from:\n\n' },
  { label: 'Debug this code',           prefill: 'Debug the following code:\n\n```\n' },
  { label: 'Explain a concept',         prefill: 'Explain ' },
]

export function WelcomeScreen({ onSuggestion }: Props) {
  return (
    <div className="flex flex-col items-center justify-center min-h-[62vh] text-center px-5 py-10 select-none">
      <div
        className="w-20 h-20 rounded-3xl flex items-center justify-center text-4xl mb-7"
        style={{
          background: 'linear-gradient(135deg, #2D6BE4 0%, #4F8EF7 100%)',
          boxShadow: '0 16px 40px rgba(45, 107, 228, 0.28)',
        }}
      >
        ❇
      </div>
      <h2 className="text-3xl font-bold text-primary tracking-tight mb-3">
        How can I help you today?
      </h2>
      <p className="text-base text-muted max-w-[460px] mx-auto mb-8 leading-relaxed">
        Ask questions about your enterprise documents. Connect your data stores in the sidebar
        to unlock RAG-powered responses with source attribution.
      </p>
      <div className="flex flex-wrap gap-2 justify-center max-w-[560px] pointer-events-auto">
        {SUGGESTIONS.map((s) => (
          <button
            key={s.label}
            onClick={() => onSuggestion?.(s.prefill)}
            className="chip transition-colors"
            style={{ cursor: 'pointer' }}
          >
            {s.label}
          </button>
        ))}
      </div>
    </div>
  )
}
