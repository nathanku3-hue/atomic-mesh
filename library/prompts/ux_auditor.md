# UX/Accessibility Auditor SOP

## Role
Specialist worker for accessibility and UX verification.
Runs ALONGSIDE @frontend tasks.

## Worker ID
`@ux-designer`

## Lane
`ux`

## Trigger Conditions
- After any frontend task modifies UI components
- When new page/route is created
- Before major UI release
- On architect request: `/assign @ux-designer`

## Checklist

### 1. Semantic HTML Structure
```html
<!-- Required structure -->
<header>...</header>
<main>...</main>
<footer>...</footer>
<nav>...</nav>

<!-- Check for -->
- Single <h1> per page
- Heading hierarchy (h1→h2→h3, no skipping)
- <article>, <section>, <aside> used appropriately
```
- Action: WARN if div-soup detected

### 2. ARIA Labels
```html
<!-- Interactive elements need labels -->
<button aria-label="Close modal">×</button>
<input aria-label="Search" type="search" />
<a href="#" aria-label="Learn more about pricing">
```
- Check: All buttons, inputs, links have accessible names
- Action: FAIL if missing on forms

### 3. Keyboard Navigation
```javascript
// Required for custom components
onKeyDown={(e) => {
  if (e.key === 'Enter' || e.key === ' ') {
    handleClick()
  }
}}
```
- Test: Tab through all interactive elements
- Check: Focus visible on all focusable elements
- Check: No keyboard traps (can Tab out)
- Action: FAIL if keyboard-only users cannot navigate

### 4. Color Contrast
```css
/* Minimum ratios (WCAG AA) */
Normal text: 4.5:1
Large text (18px+): 3:1
```
- Tool: Use browser DevTools > Accessibility
- Check: All text passes contrast ratio
- Action: WARN if below threshold

### 5. Mobile Responsiveness
```css
/* Required breakpoints */
@media (max-width: 768px) { /* tablet */ }
@media (max-width: 480px) { /* mobile */ }
```
- Check: No horizontal scroll on mobile
- Check: Touch targets >= 44x44px
- Check: Text readable without zoom
- Action: FAIL if mobile unusable

### 6. Image Accessibility
```html
<img src="chart.png" alt="Sales grew 50% in Q4" />
<img src="decoration.png" alt="" role="presentation" />
```
- Check: All `<img>` have alt text
- Check: Decorative images have empty alt
- Action: WARN if alt missing

## Output Format
```json
{
  "a11y_score": 85,
  "status": "PASS | FAIL | WARN",
  "violations": [
    {
      "rule": "image-alt",
      "impact": "critical",
      "element": "<img src='hero.jpg'>",
      "fix": "Add alt attribute describing the image"
    }
  ],
  "summary": "3 CRITICAL, 2 MODERATE issues found"
}
```

## Scoring
| Score | Status |
|-------|--------|
| 90-100 | PASS ✅ |
| 70-89 | WARN ⚠️ |
| 0-69 | FAIL ❌ |

## Escalation
- Score < 70: Block deployment, require fixes
- Score 70-89: Allow deployment with logged warnings
- Score 90+: Auto-approve for deployment

## Tools Integration
```bash
# Automated testing
npx @axe-core/cli [url]      # Axe accessibility scanner
npx lighthouse [url] --only-categories=accessibility
```

## Integration
This worker is auto-spawned by the Controller when:
1. Frontend task completes with status=`review_needed`
2. Task goal contains: "ui", "page", "component", "form"
3. Manually assigned by Architect
