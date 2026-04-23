---
paths: [
  "**/*.heex",
  "**/*.html",
  "**/*.css",
  "**/*.jsx",
  "**/*.tsx",
  "**/live/**/*.ex",
  "**/components/**/*.ex",
  "**/templates/**/*.ex"
]
excludePaths: [
  "**/contexts/**",
  "**/schemas/**",
  "**/*_test.exs",
  "**/test/**"
]
alwaysApply: true
---

# UI Design Standards - Universal Rules

**ALL UI code must follow these design standards.**

This rule automatically applies to UI-related files. For framework-specific requirements, see the relevant documentation in `docs/i/ui-design/`.

---

## Core Color Palette

### Primary Colors

| Color | Hex | Usage |
|-------|-----|-------|
| **Primary Green** | `#4CD964` | Buttons, active states, accents, CTAs |
| **Green Hover** | `#3DBF55` | Hover states for green elements |
| **Green Light** | `#E8F8EB` | Light backgrounds, badges, subtle highlights |

### Status Colors

| Color | Hex | Usage |
|-------|-----|-------|
| **Error Red** | `#FF3B30` | Error messages, destructive actions, alerts |
| **Warning Yellow** | `#FFCC00` | Warnings, caution states |
| **Success Green** | `#4CD964` | Success messages, confirmations |
| **Info Blue** | `#007AFF` | Informational messages, links |

### Neutral Colors

#### Light Mode
| Color | Hex | Usage |
|-------|-----|-------|
| **Background** | `#F5F5F7` | Page background |
| **Surface** | `#FFFFFF` | Cards, panels, modals |
| **Text Primary** | `#1C1C1E` | Main text |
| **Text Secondary** | `#8E8E93` | Secondary text, captions |
| **Border** | `#E5E5EA` | Dividers, borders |

#### Dark Mode
| Color | Hex | Usage |
|-------|-----|-------|
| **Background** | `#1C1C1E` | Page background |
| **Surface** | `#2C2C2E` | Cards, panels, modals |
| **Text Primary** | `#FFFFFF` | Main text |
| **Text Secondary** | `#8E8E93` | Secondary text, captions |
| **Border** | `#3A3A3C` | Dividers, borders |

---

## Border Radius Standards

**CRITICAL**: Border radius defines the visual language of the application.

| Element | Value | CSS/Tailwind | Usage |
|---------|-------|--------------|-------|
| **Buttons** | `9999px` | `rounded-full` | Primary, secondary, all action buttons (pill-shaped) |
| **Inputs** | `9999px` | `rounded-full` | Text inputs, search bars (pill-shaped) |
| **Cards/Modals** | `16px` | `rounded-2xl` | Cards, modal dialogs, panels |
| **Dropdowns** | `12px` | `rounded-xl` | Dropdown menus, selects |
| **Icon Buttons** | `8px` | `rounded-lg` | Small icon-only buttons |
| **Chips/Tags** | `9999px` | `rounded-full` | Status badges, tags (pill-shaped) |
| **Alerts** | `12px` | `rounded-xl` | Alert boxes, notifications |

**Key Rule**: Buttons and inputs MUST be pill-shaped (`rounded-full`).

---

## Spacing Scale

Use consistent spacing throughout the application:

| Token | Value | Tailwind | Usage |
|-------|-------|----------|-------|
| `xs` | `4px` | `gap-1` | Tight spacing, icon-text gaps |
| `sm` | `8px` | `gap-2` | Icon + text, small gaps |
| `md` | `12px` | `gap-3` | Form element spacing |
| `lg` | `16px` | `gap-4` | Card padding, section spacing |
| `xl` | `24px` | `gap-6` | Major section separation |
| `2xl` | `32px` | `gap-8` | Page-level spacing |

**Padding Scale**:
- Buttons: `px-6 py-2` (large), `px-4 py-2` (medium)
- Cards: `p-6` (24px)
- Modals: `p-8` (32px)
- Page content: `p-6` or `p-8`

---

## Typography

### Font Families
- **Primary**: System font stack (San Francisco on macOS/iOS, Segoe UI on Windows)
- **Monospace**: For code snippets

### Font Weights
| Weight | Value | Usage |
|--------|-------|-------|
| Regular | `400` | Body text |
| Medium | `500` | Buttons, labels, emphasized text |
| Semibold | `600` | Headings, section titles |
| Bold | `700` | Major headings |

### Font Sizes
| Size | Value | Tailwind | Usage |
|------|-------|----------|-------|
| xs | `12px` | `text-xs` | Captions, helper text |
| sm | `14px` | `text-sm` | Secondary text |
| base | `16px` | `text-base` | Body text (default) |
| lg | `18px` | `text-lg` | Large body text |
| xl | `20px` | `text-xl` | Small headings |
| 2xl | `24px` | `text-2xl` | Section headings |
| 3xl | `30px` | `text-3xl` | Page titles |

---

## Component Dimensions

### Layout Components

| Component | Width | Height | Tailwind |
|-----------|-------|--------|----------|
| **AppBar** | Full width | `64px` | `h-16` |
| **Left Sidebar (Open)** | `240px` | Full height | `w-64` |
| **Left Sidebar (Collapsed)** | `56px` | Full height | `w-14` |
| **Right Panel** | `320px` | Full height | `w-80` |
| **Modal (Small)** | `400px` | Auto | `max-w-md` |
| **Modal (Medium)** | `600px` | Auto | `max-w-2xl` |
| **Modal (Large)** | `800px` | Auto | `max-w-4xl` |

### UI Elements

| Element | Size | Tailwind | Notes |
|---------|------|----------|-------|
| **Icon (Small)** | `16px` | `w-4 h-4` | Inline icons |
| **Icon (Regular)** | `20px` | `w-5 h-5` | Navigation icons |
| **Icon (Large)** | `24px` | `w-6 h-6` | Header icons |
| **Avatar (Small)** | `32px` | `w-8 h-8` | User avatar in lists |
| **Avatar (Regular)** | `40px` | `w-10 h-10` | User avatar in header |
| **FAB** | `48px` | `w-12 h-12` | Floating action button |
| **Checkbox** | `20px` | `w-5 h-5` | Checkbox/radio |

---

## Icon Style

**MANDATORY**: All icons must follow outlined style.

| Property | Value | Notes |
|----------|-------|-------|
| **Style** | Outlined | No filled icons |
| **Stroke Width** | `1.5` | Consistent line weight |
| **Size** | See dimensions above | Context-dependent |
| **Color** | Text color | Inherit from parent |

**Icon Libraries**:
- **Recommended**: Heroicons (outline), Lucide Icons, Feather Icons
- **Avoid**: Filled/solid icons, mixed styles

---

## Shadow System

Use consistent shadow depths:

| Level | Tailwind | Usage |
|-------|----------|-------|
| **None** | `shadow-none` | Flat elements |
| **Subtle** | `shadow-sm` | Slight elevation |
| **Default** | `shadow-md` | Cards, panels |
| **Elevated** | `shadow-lg` | Modals, popovers |
| **Floating** | `shadow-xl` | Floating elements, FABs |

**Dark Mode**: Shadows should be less prominent in dark mode.

---

## Button Styles

### Primary Button (Action/Create)

**MUST use green color for all create/primary actions.**

```css
Background: #4CD964
Hover: #3DBF55
Text: White
Border Radius: rounded-full (pill-shaped)
Padding: px-6 py-2
Font Weight: Medium (500)
Shadow: shadow-md
```

**Example (Tailwind):**
```html
<button class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors">
  Create
</button>
```

### Secondary Button (Cancel/Neutral)

```css
Background: White
Hover: gray-50
Text: gray-700
Border: 1px solid gray-200
Border Radius: rounded-full
Padding: px-6 py-2
Font Weight: Medium (500)
Shadow: shadow-sm
```

### Danger Button (Delete/Destructive)

```css
Background: #FF3B30
Hover: red-600
Text: White
Border Radius: rounded-full
Padding: px-6 py-2
Font Weight: Medium (500)
Shadow: shadow-md
```

---

## Form Input Style

**MUST use pill-shaped inputs.**

```css
Background: #F5F5F7 (light) / #2C2C2E (dark)
Border: 1px solid transparent
Focus Border: #4CD964
Border Radius: rounded-full (pill-shaped)
Padding: px-4 py-3
Font Size: 16px (text-base)
```

**Example (Tailwind):**
```html
<input
  type="text"
  class="w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#2C2C2E] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
  placeholder="Search..."
/>
```

---

## Responsive Breakpoints

| Breakpoint | Min Width | Tailwind | Target Devices |
|------------|-----------|----------|----------------|
| `xs` | `0px` | (default) | Mobile phones |
| `sm` | `640px` | `sm:` | Large phones, small tablets |
| `md` | `768px` | `md:` | Tablets |
| `lg` | `1024px` | `lg:` | Laptops |
| `xl` | `1280px` | `xl:` | Desktops |
| `2xl` | `1536px` | `2xl:` | Large desktops |

**Mobile-First**: Design for mobile first, then enhance for larger screens.

---

## Animation & Transitions

Use subtle, fast transitions:

| Property | Duration | Easing | Tailwind |
|----------|----------|--------|----------|
| **Colors** | `150ms` | Ease | `transition-colors` |
| **Opacity** | `150ms` | Ease | `transition-opacity` |
| **Transform** | `200ms` | Ease | `transition-transform` |
| **All** | `150ms` | Ease | `transition` |

**Key Rule**: Transitions should be barely noticeable but improve feel.

---

## Accessibility

### Color Contrast

- **Normal Text**: Minimum 4.5:1 contrast ratio (WCAG AA)
- **Large Text**: Minimum 3:1 contrast ratio
- **UI Elements**: Minimum 3:1 contrast ratio

### Interactive Elements

- All interactive elements must be keyboard accessible
- Focus states must be visible (use `focus:ring-2 focus:ring-[#4CD964]`)
- Touch targets: Minimum 44x44px on mobile

### ARIA Labels

- Use semantic HTML when possible
- Add ARIA labels for icon-only buttons
- Include alt text for all images

---

## Framework-Specific Requirements

This rule defines universal standards. For framework-specific patterns:

### Material UI Applications

If your application uses Material UI design patterns (AppBar, Drawer, etc.), you must also follow:

**📚 See:** `docs/i/ui-design/material-ui/enforcement.md`

Key Material UI requirements:
- 3-panel layout (AppBar, Left Drawer, Main Content)
- Lottie animated logo
- Quick Create (+) button in AppBar
- Dual notification badge
- Warnings below items
- Feedback section at drawer bottom

### Other Frameworks

- **TailwindCSS Mappings**: `docs/i/ui-design/tailwind/index.md`
- **Phoenix/LiveView Patterns**: `docs/i/ui-design/phoenix/index.md`

---

## Validation

Before completing any UI work, verify:

- [ ] Using correct color palette (green `#4CD964` for primary actions)
- [ ] Buttons and inputs are pill-shaped (`rounded-full`)
- [ ] Cards use `rounded-2xl` (16px radius)
- [ ] Spacing follows the defined scale
- [ ] Icons use outlined style with `stroke-width="1.5"`
- [ ] Typography uses correct sizes and weights
- [ ] Dark mode colors are implemented
- [ ] Responsive design works on mobile
- [ ] Accessibility standards met (contrast, keyboard, ARIA)

**Tool**: Use the `ui-design` skill to validate compliance:
```
Use ui-design skill to validate this component
```

---

## References

For detailed specifications:
- **Complete Design System**: `docs/i/ui-design/`
- **Material UI Enforcement**: `docs/i/ui-design/material-ui/enforcement.md`
- **Component Patterns**: `docs/i/ui-design/` (buttons, forms, navigation, etc.)
- **Validation Checklist**: `docs/i/ui-design/material-ui/checklist.md`
- **Long-Running Operations (MANDATORY)**: `.claude/rules/i/progress-feedback.md` and `docs/i/ui-design/progress-feedback.md` — never leave users hanging on > 2s operations; show real-time, contextual, bounded progress

---

**Last Updated**: January 19, 2026
**Rule Version**: 1.0
