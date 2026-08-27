import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import type { Message } from '../types'
import { MetricsAndSources } from './MetricsAndSources'

interface Props {
  message: Message
}

export function ChatMessage({ message }: Props) {
  if (message.role === 'user') {
    return (
      <div className="flex justify-end my-1.5 mb-3.5">
        <div className="user-bubble">{message.content}</div>
      </div>
    )
  }

  return (
    <div className="my-1 mb-4 max-w-[88%]">
      {/* Model label — shown above assistant bubble whenever the model id is known */}
      {message.modelId && (
        <div className="text-[0.68rem] font-semibold mb-1 uppercase tracking-[0.05em] text-muted">
          {message.modelId}
        </div>
      )}

      {/* Message content */}
      <div
        className={`prose prose-invert prose-sm max-w-none text-primary leading-relaxed ${
          message.error ? 'text-red-400' : ''
        }`}
      >
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{message.content}</ReactMarkdown>
      </div>

      {/* RAG metrics + sources — present when CAS was used */}
      {(message.metrics || message.sources) && (
        <MetricsAndSources metrics={message.metrics} sources={message.sources} />
      )}

      {/* Token usage — present when a CPU model answered */}
      {message.usage && (
        <div className="mt-1 text-[0.65rem] text-muted">
          {message.usage.prompt_tokens}p + {message.usage.completion_tokens}c
          {' '}= {message.usage.total_tokens} tokens
        </div>
      )}
    </div>
  )
}
