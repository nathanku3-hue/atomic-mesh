# Lane: Frontend

## MUST
- Use `src/components/ui` for UI primitives
- Handle **Loading States** (Skeleton or Spinner)
- Handle **Error States** (Error Boundaries)
- Use `react-query` or similar for server state
- Provide fallback UI for suspense boundaries

## MUST NOT
- Use `useEffect` for data fetching (use hooks/queries)
- Hardcode hex colors (use Tailwind tokens)
- Use `z-index` > 50 (use stacking context)
- Use `!important` in CSS
- Create components > 200 lines

## Patterns
```typescript
// ✅ Good: Loading state
if (isLoading) return <Skeleton />

// ✅ Good: Error state  
if (error) return <ErrorBoundary error={error} />

// ❌ Bad: useEffect for fetching
useEffect(() => { fetch('/api/data') }, []) // DON'T
```

## Acceptance Checks
- [ ] Responsive: Tested at 375px and 1920px
- [ ] A11y: All interactives have `aria-label` or visible label
- [ ] Types: No `any` in component props
- [ ] Performance: No unnecessary re-renders
