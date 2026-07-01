<!-- Context: development/frontend/react/react-patterns | Priority: high | Version: 1.0 | Updated: 2026-03-31 -->

# React Patterns

**Purpose**: Modern React patterns, hooks, component design, and best practices for AI-agent collaboration

---

## Component Architecture

### Functional Components Only

- Always use functional components with hooks
- Never use class components in new code
- Keep components focused: one responsibility per component

### Component Organization

```
feature/
├── components/        # UI components
│   ├── FeatureCard.tsx
│   └── FeatureList.tsx
├── hooks/             # Custom hooks
│   └── useFeature.ts
├── api/               # API calls
│   └── featureApi.ts
├── types.ts           # TypeScript types
└── index.ts           # Public exports
```

### Naming Conventions

- **Components**: PascalCase (`UserProfile.tsx`)
- **Hooks**: camelCase with `use` prefix (`useAuth.ts`)
- **Utils**: camelCase (`formatDate.ts`)
- **Types**: PascalCase (`UserProfile`, `AuthState`)
- **Constants**: UPPER_SNAKE_CASE (`API_BASE_URL`)

---

## Hooks Patterns

### Custom Hooks

- Extract reusable logic into custom hooks
- Prefix with `use` (e.g., `useDebounce`, `useLocalStorage`)
- Return consistent shapes: `{ data, loading, error }` or `[value, setter]`

### Common Patterns

```typescript
// Data fetching hook pattern
function useData<T>(url: string) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  // ...
  return { data, loading, error };
}
```

### Rules of Hooks

- Only call hooks at the top level
- Only call hooks from React functions
- Use `useMemo` / `useCallback` for expensive computations and stable references
- Avoid premature memoization — profile first

---

## State Management

### Local State

- `useState` for simple component state
- `useReducer` for complex state logic

### Server State

- **TanStack Query** (preferred) for API data, caching, and synchronization
- Avoid storing server data in client state

### Global Client State

- **Zustand** (preferred) for simple global state
- **Context API** for theme, auth, locale (low-frequency updates)
- Avoid Context for high-frequency updates (causes re-renders)

---

## Performance Patterns

- **Lazy loading**: `React.lazy()` + `Suspense` for route-level code splitting
- **Memoization**: `React.memo()` for expensive pure components
- **Virtual lists**: Use `react-window` or `@tanstack/react-virtual` for long lists
- **Debounce**: Debounce search inputs and resize handlers
- **Optimistic updates**: Update UI before server confirms (with rollback)

---

## TypeScript Integration

- Always use TypeScript strict mode
- Define explicit prop types (avoid `any`)
- Use discriminated unions for complex state
- Export types alongside components

```typescript
// Props pattern
interface ButtonProps {
  variant: 'primary' | 'secondary' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}
```

---

## Testing Patterns

- **Unit tests**: React Testing Library + Vitest/Jest
- **Test behavior, not implementation**: Query by role, text, label
- **User-centric assertions**: `screen.getByRole()`, `userEvent.click()`
- **Mock sparingly**: Prefer integration tests over mocked units

---

## Related Context

- **React Navigation** → `navigation.md`
- **Frontend Navigation** → `../navigation.md`
- **Code Quality** → `../../../core/standards/code-quality.md`
- **Test Coverage** → `../../../core/standards/test-coverage.md`
- **When to Delegate** → `../when-to-delegate.md`
