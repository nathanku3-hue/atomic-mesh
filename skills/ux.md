# Lane: UX (Accessibility)

## MUST
- Use semantic HTML (`header`, `main`, `nav`, `footer`)
- Ensure single `<h1>` per page with proper hierarchy
- Add `aria-label` to all interactive elements
- Support keyboard navigation (Tab, Enter, Space)
- Meet WCAG AA contrast ratios (4.5:1 text, 3:1 large)

## MUST NOT
- Use `<div>` for clickable elements (use `<button>`)
- Skip heading levels (h1→h3)
- Create keyboard traps
- Use color alone to convey meaning
- Use `outline: none` without alternative

## Patterns
```html
<!-- ✅ Good: Semantic button -->
<button aria-label="Close modal" onClick={onClose}>×</button>

<!-- ❌ Bad: Div as button -->
<div onClick={onClose}>×</div>

<!-- ✅ Good: Heading hierarchy -->
<h1>Page Title</h1>
<h2>Section</h2>
<h3>Subsection</h3>

<!-- ❌ Bad: Skipped heading -->
<h1>Page Title</h1>
<h3>Subsection</h3> <!-- Missing h2! -->
```

## Acceptance Checks
- [ ] Keyboard: All actions reachable via Tab + Enter
- [ ] Screen Reader: ARIA labels on interactives
- [ ] Contrast: 4.5:1 ratio for body text
- [ ] Mobile: Touch targets >= 44x44px
