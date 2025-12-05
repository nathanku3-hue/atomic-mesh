# TYPESCRIPT NEXT.JS ARCHITECTURE STANDARD
## Atomic Mesh Central Library v1.0

---

## 1. App Router Structure

### Recommended Layout
```
/src
  /app                      # App Router (Next.js 13+)
    layout.tsx              # Root layout
    page.tsx                # Home page
    /api                    # API Routes
      /auth
        /[...nextauth]
          route.ts
      /users
        route.ts            # GET /api/users
        /[id]
          route.ts          # GET/PUT/DELETE /api/users/:id
    /(dashboard)            # Route group
      /settings
        page.tsx
        
  /components
    /ui                     # Atomic components (Button, Input)
    /features               # Feature components (UserCard, AuthForm)
    /layouts                # Layout components (Sidebar, Header)
    
  /lib                      # Business logic, utilities
    /api                    # API client functions
    /hooks                  # Custom React hooks
    /utils                  # Pure utility functions
    /db                     # Database clients, queries
    
  /types                    # TypeScript types/interfaces
  
  /styles                   # Global styles
```

---

## 2. API Route Pattern

### File Structure
```typescript
// /app/api/users/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { getServerSession } from 'next-auth';

// Schema at top
const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1)
});

// Handler
export async function POST(request: NextRequest) {
  try {
    // 1. Auth check
    const session = await getServerSession();
    if (!session) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }
    
    // 2. Parse and validate
    const body = await request.json();
    const validated = CreateUserSchema.parse(body);
    
    // 3. Business logic (via lib/ functions)
    const user = await createUser(validated);
    
    // 4. Return response
    return NextResponse.json(user, { status: 201 });
    
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors }, { status: 400 });
    }
    console.error('API Error:', error);
    return NextResponse.json({ error: 'Internal error' }, { status: 500 });
  }
}
```

---

## 3. Component Pattern

### File Structure
```
/components/features/UserCard/
  index.ts                  # Re-export
  UserCard.tsx              # Component
  UserCard.test.tsx         # Tests
  UserCard.types.ts         # Types (if complex)
```

### Component Template
```tsx
// UserCard.tsx
'use client'; // Only if needed

import { FC } from 'react';

interface UserCardProps {
  user: User;
  onEdit?: (id: string) => void;
}

export const UserCard: FC<UserCardProps> = ({ user, onEdit }) => {
  return (
    <div className="rounded-lg border p-4">
      <h3>{user.name}</h3>
      {onEdit && (
        <button onClick={() => onEdit(user.id)}>Edit</button>
      )}
    </div>
  );
};
```

---

## 4. Server/Client Boundary

### Rules
- Default to Server Components
- Add `'use client'` only when needed:
  - useState, useEffect, custom hooks
  - Event handlers (onClick, onChange)
  - Browser APIs

### Pattern
```tsx
// ServerComponent.tsx (default)
async function ServerComponent() {
  const data = await fetchData(); // Direct DB call OK
  return <ClientComponent data={data} />;
}

// ClientComponent.tsx
'use client';
function ClientComponent({ data }) {
  const [state, setState] = useState(data);
  // Interactive logic here
}
```

---

## 5. Data Fetching

### Server Components
```tsx
// Direct async/await in components
async function UserList() {
  const users = await prisma.user.findMany();
  return <ul>{users.map(u => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

### Client Components
```tsx
'use client';
import useSWR from 'swr';

function UserList() {
  const { data, error, isLoading } = useSWR('/api/users', fetcher);
  if (isLoading) return <Skeleton />;
  if (error) return <Error />;
  return <ul>{data.map(u => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

---

## 6. Type Safety

### API Response Types
```typescript
// /types/api.ts
export interface ApiResponse<T> {
  data?: T;
  error?: string;
  message?: string;
}

export interface PaginatedResponse<T> extends ApiResponse<T[]> {
  total: number;
  page: number;
  limit: number;
}
```

### Zod Schema to Type
```typescript
import { z } from 'zod';

export const UserSchema = z.object({
  id: z.string(),
  email: z.string().email(),
  name: z.string()
});

export type User = z.infer<typeof UserSchema>;
```

---

## 7. Error Handling

### API Routes
```typescript
// /lib/api/errors.ts
export class ApiError extends Error {
  constructor(
    public message: string,
    public statusCode: number = 500,
    public code?: string
  ) {
    super(message);
  }
}

export function handleApiError(error: unknown) {
  if (error instanceof ApiError) {
    return NextResponse.json(
      { error: error.message, code: error.code },
      { status: error.statusCode }
    );
  }
  console.error('Unhandled error:', error);
  return NextResponse.json(
    { error: 'Internal server error' },
    { status: 500 }
  );
}
```
