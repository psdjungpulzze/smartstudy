# User Story Template

## Story Format

```
As a [type of user],
I want [goal/desire],
So that [benefit/value].
```

---

## User Story Card

### US-[NUMBER]: [Story Title]

**Addresses Requirements**: FR-XXX, FR-XXX

**Epic**: [Parent epic if applicable]

**Priority**: Must Have / Should Have / Could Have / Won't Have

**Story Points**: [Points or T-shirt size]

**Status**: Backlog / Ready / In Progress / Done

---

#### User Story

```
As a [user type],
I want [action/goal],
So that [benefit].
```

---

#### Acceptance Criteria

Using Given-When-Then format:

**Scenario 1: [Happy path]**
```
Given [precondition]
When [action]
Then [expected result]
```

**Scenario 2: [Alternative path]**
```
Given [precondition]
When [action]
Then [expected result]
```

**Scenario 3: [Error case]**
```
Given [precondition]
When [action]
Then [expected error handling]
```

---

#### Additional Criteria

- [ ] [Specific requirement 1]
- [ ] [Specific requirement 2]
- [ ] [Performance requirement]
- [ ] [Security requirement]

---

#### Technical Notes

[Technical considerations, dependencies, or implementation hints]

---

#### Design References

- [Link to mockup/wireframe]
- [Link to design spec]

---

#### Dependencies

- **Blocked by**: [Other stories or tasks]
- **Blocks**: [Stories that depend on this]
- **Related**: [Related stories]

---

## Example User Stories

### Example 1: Login Feature

#### US-001: User Login

**Epic**: Authentication

**Priority**: Must Have

**Story Points**: 3

---

#### User Story

```
As a registered user,
I want to log into my account with email and password,
So that I can access my personalized dashboard.
```

---

#### Acceptance Criteria

**Scenario 1: Successful login**
```
Given I am on the login page
And I have a registered account
When I enter valid email and password
And click the "Log In" button
Then I am redirected to my dashboard
And I see a welcome message with my name
```

**Scenario 2: Invalid credentials**
```
Given I am on the login page
When I enter invalid email or password
And click the "Log In" button
Then I see an error message "Invalid email or password"
And I remain on the login page
And the password field is cleared
```

**Scenario 3: Account locked**
```
Given I have failed login 5 times
When I attempt to log in again
Then I see a message "Account locked. Try again in 30 minutes."
And the login form is disabled
```

---

#### Additional Criteria

- [ ] Password field masks input
- [ ] "Remember me" option available
- [ ] "Forgot password" link visible
- [ ] Login attempt logged for security
- [ ] Session expires after 24 hours of inactivity

---

### Example 2: Search Feature

#### US-002: Product Search

**Epic**: Product Discovery

**Priority**: Must Have

**Story Points**: 5

---

#### User Story

```
As a customer,
I want to search for products by name or category,
So that I can quickly find items I want to purchase.
```

---

#### Acceptance Criteria

**Scenario 1: Search by keyword**
```
Given I am on any page with the search bar
When I enter "wireless headphones" in the search field
And press Enter or click the search icon
Then I see a list of products matching "wireless headphones"
And results are sorted by relevance
And I see the total number of results
```

**Scenario 2: No results**
```
Given I am on any page with the search bar
When I search for "xyznonexistent123"
Then I see a message "No products found for 'xyznonexistent123'"
And I see suggested search terms
```

**Scenario 3: Search suggestions**
```
Given I am typing in the search field
When I have typed at least 2 characters
Then I see up to 5 search suggestions
And suggestions update as I type
```

---

#### Additional Criteria

- [ ] Search results load within 500ms
- [ ] Support for special characters
- [ ] Search history saved (last 10 searches)
- [ ] Filter options available on results page

---

## User Story Writing Checklist

### INVEST Criteria

- [ ] **I**ndependent - Can be developed separately
- [ ] **N**egotiable - Details can be discussed
- [ ] **V**aluable - Provides value to user/business
- [ ] **E**stimable - Can estimate effort
- [ ] **S**mall - Fits in one sprint
- [ ] **T**estable - Can verify completion

### Quality Checks

- [ ] Written from user perspective
- [ ] Clear and concise
- [ ] Single piece of functionality
- [ ] Acceptance criteria are specific
- [ ] No technical jargon (unless user story is for technical user)
- [ ] Testable scenarios included

---

## Story Mapping Template

```
                    User Journey
┌─────────────────────────────────────────────────────────┐
│  Browse  │  Search  │  Select  │  Purchase  │  Review  │
└─────────────────────────────────────────────────────────┘
     │          │          │           │           │
     ▼          ▼          ▼           ▼           ▼
┌─────────┐ ┌────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐
│ US-010  │ │ US-002 │ │ US-015  │ │ US-020  │ │ US-030 │
│ Homepage│ │ Search │ │ Product │ │ Checkout│ │ Rate   │
│ listing │ │        │ │ detail  │ │         │ │ product│
└─────────┘ └────────┘ └─────────┘ └─────────┘ └────────┘
     │          │          │           │           │
     ▼          ▼          ▼           ▼           ▼
┌─────────┐ ┌────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐
│ US-011  │ │ US-003 │ │ US-016  │ │ US-021  │ │ US-031 │
│ Category│ │ Filter │ │ Add to  │ │ Payment │ │ Write  │
│ filter  │ │ results│ │ cart    │ │         │ │ review │
└─────────┘ └────────┘ └─────────┘ └─────────┘ └────────┘
```

---

## Backlog Template

| ID | Title | Epic | Priority | Points | Status |
|----|-------|------|----------|--------|--------|
| US-001 | User Login | Auth | Must Have | 3 | Ready |
| US-002 | Product Search | Discovery | Must Have | 5 | Ready |
| US-003 | Filter Results | Discovery | Should Have | 3 | Backlog |
| US-004 | User Registration | Auth | Must Have | 5 | In Progress |

---

## User Story Validation Rules

- [ ] Every user story MUST reference at least one requirement (FR-XXX)
- [ ] Every requirement MUST be referenced by at least one user story
- [ ] Run cross-check: extract all FR-XXX from requirements.md, verify each appears in at least one user story
- [ ] No orphaned stories (stories that don't map to any requirement)
