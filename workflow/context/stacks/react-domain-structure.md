<!-- Context: stacks/react-domain-structure | Priority: high | Version: 1.0 | Updated: 2026-05-07 -->

# React Frontend — Domain-Driven Structure with PWA

**Purpose**: Scalable React frontend pattern using context-per-domain, custom hooks, and PWA offline-first. Complements `stacks/react.md` with production patterns for medium-to-large apps.

**When to use**: SPAs with 5+ business domains, offline support requirements, or teams needing predictable module boundaries.

---

## Directory Layout

```
frontend/
├── Dockerfile                          # Multi-stage (see standards/dockerfile-patterns.md)
├── nginx.conf                          # Production: nginx serves /dist
├── vite.config.js                      # alias @shared → ../shared/
├── vitest.config.js
├── tailwind.config.js
├── index.html
└── src/
    ├── main.jsx                        # Entry: ReactDOM.render
    ├── App.jsx                         # Router + context providers composition
    ├── index.css                       # Tailwind imports + globals
    │
    ├── api/                            # Axios instance + interceptors
    ├── constants/                      # Frontend-only enums (routes, UI labels)
    │
    ├── contexts/                       # One context per business domain
    │   ├── AuthContext.jsx
    │   ├── WalletContext.jsx
    │   ├── CryptoContext.jsx
    │   └── <Domain>Context.jsx
    │
    ├── hooks/                          # useXxx hook per context + cross-cutting
    │   ├── useAuth.js                  # Thin re-export: useContext(AuthContext)
    │   ├── useWallet.js
    │   ├── useOfflineQuery.js          # PWA offline read
    │   ├── useOfflineMutation.js       # PWA offline write + sync
    │   └── useResponsive.js
    │
    ├── components/                     # UI components, grouped by domain
    │   ├── common/                     # Buttons, modals, inputs — generic
    │   ├── layout/                     # Header, sidebar, footer
    │   ├── <domain>/                   # Domain-specific components
    │   └── widget/                     # Dashboard widgets (grid-layout)
    │
    ├── pages/                          # Route-level components
    ├── services/                       # Non-HTTP services (storage, analytics, PWA)
    │   ├── offline-storage.js          # IndexedDB wrapper
    │   └── background-sync.js          # Service Worker sync queue
    │
    ├── utils/                          # Pure helpers (formatters, validators)
    └── __tests__/                      # Mirror of src/
```

---

## Context-per-Domain Pattern

**One context per business domain.** Never one god-context.

```jsx
// src/contexts/WalletContext.jsx
import { createContext, useState, useCallback } from 'react'
import { useQuery, useMutation } from '@tanstack/react-query'
import api from '../api'

export const WalletContext = createContext(null)

export function WalletProvider({ children }) {
  const [activeWalletId, setActiveWalletId] = useState(null)

  const { data: wallets = [], isLoading } = useQuery({
    queryKey: ['wallets'],
    queryFn: () => api.get('/wallets').then(r => r.data)
  })

  const createWallet = useMutation({
    mutationFn: (payload) => api.post('/wallets', payload)
  })

  const value = { wallets, isLoading, activeWalletId, setActiveWalletId, createWallet }
  return <WalletContext.Provider value={value}>{children}</WalletContext.Provider>
}
```

**Composition in `App.jsx`:**

```jsx
<AuthProvider>
  <WalletProvider>
    <CryptoProvider>
      <Router>{routes}</Router>
    </CryptoProvider>
  </WalletProvider>
</AuthProvider>
```

---

## useXxx Hook Pattern

**Thin re-export of `useContext`** — hides context wiring from consumers:

```javascript
// src/hooks/useWallet.js
import { useContext } from 'react'
import { WalletContext } from '../contexts/WalletContext'

export function useWallet() {
  const ctx = useContext(WalletContext)
  if (!ctx) throw new Error('useWallet must be used within WalletProvider')
  return ctx
}
```

**In components:**

```jsx
function WalletList() {
  const { wallets, isLoading } = useWallet()  // Clean API
  if (isLoading) return <Spinner />
  return wallets.map(w => <WalletCard key={w.id} {...w} />)
}
```

**Rule**: components **never** `useContext(WalletContext)` directly — always via `useWallet()`. Facilita mocks em testes.

---

## PWA Offline-first

### Setup

```javascript
// vite.config.js
import { VitePWA } from 'vite-plugin-pwa'

export default {
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      workbox: {
        runtimeCaching: [
          { urlPattern: /\/api\/(?!auth)/, handler: 'NetworkFirst' }
        ]
      },
      manifest: { name: 'MyApp', short_name: 'myapp', theme_color: '#0a0' }
    })
  ]
}
```

### Offline Query Hook

```javascript
// src/hooks/useOfflineQuery.js
import { useQuery } from '@tanstack/react-query'
import { getFromIndexedDB, saveToIndexedDB } from '../services/offline-storage'

export function useOfflineQuery({ queryKey, queryFn, ...opts }) {
  return useQuery({
    queryKey,
    queryFn: async () => {
      try {
        const fresh = await queryFn()
        await saveToIndexedDB(queryKey, fresh)
        return fresh
      } catch (e) {
        const cached = await getFromIndexedDB(queryKey)
        if (cached) return cached
        throw e
      }
    },
    ...opts
  })
}
```

### Offline Mutation Hook

```javascript
// src/hooks/useOfflineMutation.js
export function useOfflineMutation({ mutationFn, queueKey }) {
  return useMutation({
    mutationFn: async (payload) => {
      if (navigator.onLine) return mutationFn(payload)
      await queueForBackgroundSync(queueKey, payload)
      return { queued: true, payload }
    }
  })
}
```

Combined com service worker (`background-sync.js`) que reexecuta quando volta online.

---

## State Management Strategy

| Scope | Tool |
|-------|------|
| Server state | `@tanstack/react-query` |
| UI state cross-component | Context + `useState` |
| Forms | `react-hook-form` + `zod` |
| URL state | `react-router-dom` v6 |
| Offline state | IndexedDB via `offline-storage.js` |

**Não use Redux** a menos que tenha ≥15 reducers interligados.

---

## Testing Stack

- **Vitest** (ESM-native) + **@testing-library/react** + **jsdom**
- Mock contexts: `render(<Component />, { wrapper: MockWalletProvider })`

---

## Shared Module Integration

```javascript
// vite.config.js
resolve: { alias: { '@shared': path.resolve(__dirname, '../shared') } }
```

**Nunca** use symlinks absolutos — quebra em CI.

---

## Related Context

- `stacks/react.md` · `stacks/ui-styling.md` · `stacks/fullstack-containerized.md` · `standards/test-coverage.md`
