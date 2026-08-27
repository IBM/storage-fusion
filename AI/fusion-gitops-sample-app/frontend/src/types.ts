// ─────────────────────────────────────────────────────────────────────────────
// Shared
// ─────────────────────────────────────────────────────────────────────────────

export interface VectorStore {
  id: string
  name: string
}

// ─────────────────────────────────────────────────────────────────────────────
// Unified model registry — returned by GET /api/models
// The backend never exposes runtime (gateway vs cpu); the frontend only sees
// the model id, its capabilities, and whether it is the default selection.
// ─────────────────────────────────────────────────────────────────────────────

export interface ModelInfo {
  id: string
  capabilities: string[]   // e.g. ["chat","code","summarize","rag"]
  default: boolean
}

// ─────────────────────────────────────────────────────────────────────────────
// Unified chat request / response  (POST /api/chat)
// ─────────────────────────────────────────────────────────────────────────────

export interface HistoryMessage {
  role: 'user' | 'assistant'
  content: string
}

export interface ChatRequest {
  query: string
  vector_store_id: string
  model_id: string            // explicit model; empty string → backend uses default
  auto_detect: boolean        // true → backend picks model via capability matching
  max_tokens?: number
  temperature?: number
  history: HistoryMessage[]
}

export interface SourceAttribution {
  source_file: string
  document_id: string
  relevance_score: number
  content_snippet: string
  line_start?: number
  line_end?: number
  metadata: Record<string, unknown>
}

export interface ResponseMetrics {
  processing_time: number
  sources_count: number
  cas_search_count: number
}

export interface ChatResponse {
  response: string
  model_id: string                    // which model actually answered
  sources: SourceAttribution[]
  metrics?: ResponseMetrics | null    // present when RAG/CAS was used
  usage?: CpuUsage | null             // present when a CPU model answered
}

// ─────────────────────────────────────────────────────────────────────────────
// App config  (GET /api/config)
// ─────────────────────────────────────────────────────────────────────────────

export interface AppConfig {
  cas_endpoint: string
  model_gateway_endpoint: string
  model_name: string
  cas_vector_store_id: string
}

// ─────────────────────────────────────────────────────────────────────────────
// CPU usage counter — surfaced in the response when a CPU model answers
// ─────────────────────────────────────────────────────────────────────────────

export interface CpuUsage {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
}

// ─────────────────────────────────────────────────────────────────────────────
// Unified message — used in the chat list for every response
// ─────────────────────────────────────────────────────────────────────────────

export interface Message {
  id: string
  role: 'user' | 'assistant'
  content: string
  // Set on assistant messages
  modelId?: string
  sources?: SourceAttribution[]
  metrics?: ResponseMetrics
  usage?: CpuUsage | null
  error?: boolean
}
