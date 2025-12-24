# Lane: Frontend

## DIRECTIVE
You are a frontend specialist. Build robust, accessible React components.

---

## MUST (Required)
- Use `src/components/ui` for primitives
- Handle **Loading States** (Skeleton or Spinner)
- Handle **Error States** (Error Boundaries)
- Use `react-query` for server state
- Provide fallback UI for suspense

## SHOULD (Recommended)
- Keep components under 200 lines
- Extract hooks for complex logic
- Use TypeScript strict mode
- Memoize expensive computations

## AVOID (Forbidden)
- ❌ `useEffect` for data fetching
- ❌ Hardcoded hex colors (use Tailwind)
- ❌ `z-index` > 50
- ❌ `!important` in CSS
- ❌ `any` types in props

---

## EXAMPLES

### ✅ Good: Loading State
```tsx
if (isLoading) return <Skeleton className="h-10 w-full" />
if (error) return <ErrorBoundary error={error} />
return <Component data={data} />
```

### ❌ Bad: useEffect Fetching
```tsx
// DON'T DO THIS
useEffect(() => {
  fetch('/api/data').then(setData)
}, [])
```

---

## CONSTRAINTS
- Do NOT modify files outside `src/`
- Do NOT add new dependencies without approval
- Do NOT remove existing tests

## OUTPUT EXPECTATIONS
- Provide complete, working code
- Include TypeScript types
- Add inline comments for complex logic

## EVIDENCE (Acceptance Checks)
- [ ] Responsive: Tested at 375px and 1920px
- [ ] A11y: All interactives have accessible names
- [ ] Types: No `any` in component props
- [ ] Tests: Unit tests pass
