# ADR-004: Multi-Role Authentication Architecture

## Status

Accepted

## Date

2026-04-17

## Context

FunSheep needs authentication for three end-user roles (student, parent, teacher) plus platform administrators. Industry best practice for educational platforms uses a single identity provider with RBAC, not separate auth systems per role. Need to decide how to implement this with Interactor Account Server.

Key requirements:
- Students study and take assessments
- Parents monitor their children's progress and readiness
- Teachers monitor their class students' progress and generate reports
- Platform admins manage the system (user management, system metrics)
- Parents and teachers can each be linked to multiple students
- A single login experience for all end users (no role-specific login pages)

## Decision

FunSheep will use a two-tier authentication architecture built on Interactor Account Server:

### Tier 1: End Users (Student, Parent, Teacher)

- **Auth flow**: Interactor User JWT via OAuth 2.0 / OIDC Authorization Code flow
- **Login**: Single login page for all end users at `/auth/login`
- **Role storage**: Interactor user `metadata.role` field (values: `"student"`, `"parent"`, `"teacher"`)
- **Role selection**: During first login/registration, users choose their role. This is stored in Interactor `metadata.role` via API call and mirrored to the local `user_roles` table.
- **Post-login routing**: Role determines landing page:
  - `student` → `/dashboard` (study dashboard)
  - `parent` → `/parent/children` (children overview)
  - `teacher` → `/teacher/classes` (class overview)
- **Social login**: Google OAuth works for all roles (same OIDC flow)

### Tier 2: Platform Admins

- **Auth flow**: Interactor Admin JWT tier via `/api/v1/admin/login`
- **Login**: Separate admin portal at `/admin`
- **Privileges**: Admin-tier JWTs have elevated privileges and different signing claims
- **Separation**: Completely separate Phoenix pipeline, layout, and session from the user portal

### Role Enforcement

- **Phoenix Plugs**: `RequireRole` plug checks `metadata.role` on every request and returns 403 on mismatch
- **Guardian access**: `RequireGuardian` plug verifies an active `student_guardians` record before allowing parent/teacher access to student data
- **Local mirror**: `user_roles` table mirrors Interactor `metadata.role` for fast local queries and joins

### Relationships

- Parent/teacher to student links are stored in FunSheep's `student_guardians` table
- Links use an invite/accept flow: guardian sends request, student must accept
- Each guardian can be linked to multiple students; each student can have multiple guardians
- `relationship_type` distinguishes `parent` from `teacher`

## Consequences

### Positive

- Single auth system for all end users (no separate login pages per role)
- Roles are just metadata -- easy to add new roles later (e.g., tutor, school admin)
- Admin portal fully separated from user portal (different JWT tier, different privilege level)
- Social login (Google) works for all roles without additional configuration
- Interactor handles all auth complexity (password hashing, MFA, token refresh)
- Guardian relationships are application-level data, decoupled from the identity provider

### Negative

- Role changes require updating Interactor user metadata via API call (not instant local update)
- `metadata.role` is not enforced by Interactor -- FunSheep must validate on every request via Plugs
- Admin JWT and User JWT are different formats -- admin portal code is separate from user portal
- Guardian relationship validation adds a database query on parent/teacher requests to student data

## Alternatives Considered

1. **Separate Interactor applications per role** -- Would create three OAuth clients and fragment user management. Over-complex for the benefit gained. Users who are both a parent and teacher would need separate accounts.

2. **Custom auth with Ecto schemas** -- Reinvents what Interactor already provides (password hashing, JWT signing, MFA, social login). Creates ongoing maintenance burden and security risk. Not recommended per project security rules.

3. **Interactor Organizations for schools** -- Maps school structure to Interactor's organization model. Doesn't fit because the parent role is not school-affiliated, and the org model adds unnecessary complexity for simple role-based access control.

4. **Role as a separate Interactor claim** -- Using custom JWT claims instead of metadata. Interactor doesn't support custom claims in the User JWT; metadata is the correct extension point.
