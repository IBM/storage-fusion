import type {
  AppConfig,
  ChatRequest,
  ChatResponse,
  ModelInfo,
  VectorStore,
} from './types'

const BASE = '/api'

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    const text = await res.text().catch(() => res.statusText)
    throw new Error(text || `HTTP ${res.status}`)
  }
  return res.json() as Promise<T>
}

export const api = {
  getConfig: () => request<AppConfig>('/config'),

  getVectorStores: () => request<VectorStore[]>('/vector-stores'),

  /** Returns all models (gateway + CPU) as ModelInfo objects. */
  getModels: () => request<ModelInfo[]>('/models'),

  /** Unified chat — works for gateway and CPU models alike. */
  chat: (body: ChatRequest) =>
    request<ChatResponse>('/chat', {
      method: 'POST',
      body: JSON.stringify(body),
    }),
}
