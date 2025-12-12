# TYPESCRIPT NEXT.JS FOLDER STRUCTURE STANDARD
## Atomic Mesh Central Library v1.0

---

## 1. Golden Structure

```
project-root/
├── src/
│   ├── app/                          # Next.js App Router
│   │   ├── layout.tsx                # Root layout
│   │   ├── page.tsx                  # Home page
│   │   ├── globals.css               # Global styles
│   │   ├── (auth)/                   # Route group: auth pages
│   │   │   ├── login/
│   │   │   │   └── page.tsx
│   │   │   └── register/
│   │   │       └── page.tsx
│   │   ├── (dashboard)/              # Route group: protected
│   │   │   ├── layout.tsx
│   │   │   └── settings/
│   │   │       └── page.tsx
│   │   └── api/                      # API Routes
│   │       ├── auth/
│   │       │   └── [...nextauth]/
│   │       │       └── route.ts
│   │       └── users/
│   │           ├── route.ts          # GET, POST
│   │           └── [id]/
│   │               └── route.ts      # GET, PUT, DELETE
│   │
│   ├── components/
│   │   ├── ui/                       # Atomic: Button, Input, Card
│   │   │   ├── Button.tsx
│   │   │   ├── Input.tsx
│   │   │   └── index.ts              # Barrel export
│   │   ├── features/                 # Domain: UserCard, AuthForm
│   │   │   └── auth/
│   │   │       ├── LoginForm.tsx
│   │   │       └── index.ts
│   │   └── layouts/                  # Layout: Sidebar, Header
│   │       ├── Sidebar.tsx
│   │       └── Header.tsx
│   │
│   ├── lib/                          # Business logic
│   │   ├── api/                      # API client functions
│   │   │   └── users.ts
│   │   ├── db/                       # Database
│   │   │   ├── prisma.ts             # Prisma client
│   │   │   └── models/
│   │   ├── hooks/                    # Custom hooks
│   │   │   └── useUser.ts
│   │   ├── utils/                    # Pure utilities
│   │   │   ├── format.ts
│   │   │   └── validation.ts
│   │   └── auth/                     # Auth utilities
│   │       └── session.ts
│   │
│   ├── types/                        # TypeScript types
│   │   ├── api.ts
│   │   ├── user.ts
│   │   └── index.ts
│   │
│   └── styles/                       # Additional styles
│       └── components/
│
├── public/                           # Static assets
│   ├── images/
│   └── fonts/
│
├── tests/                            # Test files (alternative to co-location)
│   ├── unit/
│   └── e2e/
│
├── scripts/                          # Build/deploy scripts
│   └── seed.ts
│
├── docs/                             # Documentation
│
├── .env.example
├── .env.local                        # (gitignored)
├── .gitignore
├── next.config.ts
├── tsconfig.json
├── package.json
├── tailwind.config.ts
└── README.md
```

---

## 2. Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Components | PascalCase | `UserCard.tsx` |
| Hooks | camelCase with `use` | `useUser.ts` |
| Utilities | camelCase | `formatDate.ts` |
| API routes | lowercase | `route.ts` |
| Types | PascalCase | `User.ts` |
| Constants | UPPER_SNAKE | `API_URL` |

---

## 3. Import Aliases

```json
// tsconfig.json
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"],
      "@/components/*": ["./src/components/*"],
      "@/lib/*": ["./src/lib/*"],
      "@/types/*": ["./src/types/*"]
    }
  }
}
```

### Usage
```typescript
// ✅ Good
import { Button } from '@/components/ui';
import { formatDate } from '@/lib/utils/format';

// ❌ Bad
import { Button } from '../../../components/ui/Button';
```

---

## 4. Gap Analysis Triggers

| Pattern | Violation | Action |
|---------|-----------|--------|
| Files in root src/ | `helpers.ts` in `/src` | Move to `/src/lib/utils/` |
| Mixed component types | UI + Feature in same folder | Split into `/ui` and `/features` |
| No barrel exports | Direct imports everywhere | Add `index.ts` |
| Flat components | All in `/components` | Organize by type |
| Utils in components | `formatDate` in component | Move to `/lib/utils` |
| Types scattered | Types in random files | Centralize in `/types` |

---

## 5. Forbidden Patterns

- ❌ `helpers.ts` / `utils.ts` in root (too vague)
- ❌ `components/index.tsx` as component (confusing)
- ❌ API logic in components
- ❌ `any` type usage
- ❌ Hardcoded strings (use constants)
