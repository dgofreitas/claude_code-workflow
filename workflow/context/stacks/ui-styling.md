<!-- Context: development/ui-styling-standards | Priority: high | Version: 2.0 | Updated: 2026-03-29 -->
# UI Styling Standards

**Framework**: Tailwind CSS (script tag) + Flowbite (default component lib)
**Approach**: Mobile-first, utility-first CSS
**Colors**: OKLCH format, semantic naming (`--primary`, not `--blue`)
**Override**: `!important` only for framework overrides

---

## Framework Setup

```html
<!-- Tailwind (✅ script tag for JIT) -->
<script src="https://cdn.tailwindcss.com"></script>

<!-- Flowbite -->
<link href="https://cdn.jsdelivr.net/npm/flowbite@2.0.0/dist/flowbite.min.css" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/flowbite@2.0.0/dist/flowbite.min.js"></script>

<!-- Fonts -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

---

## Breakpoints & Responsive

| Prefix | Min Width | Use Case |
|--------|-----------|----------|
| (base) | 0px | Mobile styles (default) |
| `sm:` | 640px | Large phones |
| `md:` | 768px | Tablets |
| `lg:` | 1024px | Laptops |
| `xl:` | 1280px | Desktops |
| `2xl:` | 1536px | Large screens |

```html
<!-- Mobile: stack, Desktop: side-by-side -->
<div class="flex flex-col md:flex-row">
  <div class="w-full md:w-1/2">Left</div>
  <div class="w-full md:w-1/2">Right</div>
</div>
```

**Test at**: 375px, 768px, 1024px, 1440px. Touch targets min 44x44px.

---

## Colors

**Rule**: NEVER use Bootstrap blue (#007bff) unless explicitly requested.

```css
--primary: oklch(0.6489 0.2370 26.9728);   /* Vibrant orange */
--accent: oklch(0.5635 0.2408 260.8178);    /* Rich purple */
--info: oklch(0.6200 0.1900 260);           /* Modern blue */
--success: oklch(0.7323 0.2492 142.4953);   /* Fresh green */
```

- Use semantic naming (`--primary`, `--accent`)
- WCAG AA: 4.5:1 contrast minimum
- Light component → dark background (and vice versa)

---

## Layout Patterns

```html
<!-- Flex: horizontal -->
<div class="flex items-center gap-4">...</div>

<!-- Flex: centered -->
<div class="flex items-center justify-center min-h-screen">...</div>

<!-- Grid: responsive cards -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">...</div>

<!-- Grid: dashboard -->
<div class="grid grid-cols-12 gap-4">
  <aside class="col-span-12 lg:col-span-3">Sidebar</aside>
  <main class="col-span-12 lg:col-span-9">Content</main>
</div>

<!-- Container -->
<div class="container mx-auto px-4 max-w-7xl">...</div>
```

---

## Typography

```html
<h1 class="text-4xl md:text-5xl lg:text-6xl font-bold">Main</h1>
<h2 class="text-3xl md:text-4xl font-semibold">Section</h2>
<p class="text-base md:text-lg leading-relaxed">Body</p>
<p class="text-sm text-gray-600">Secondary</p>
```

- **Body font**: `'Inter', sans-serif !important`
- **Line length**: 60-80 chars, **line height**: 1.5-1.75, **min size**: 16px

---

## Component Patterns

```html
<!-- Primary button -->
<button class="bg-primary text-primary-foreground px-6 py-3 rounded-lg font-medium hover:opacity-90 transition-opacity">Action</button>

<!-- Card -->
<div class="bg-card text-card-foreground rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow">
  <h3 class="text-xl font-semibold mb-2">Title</h3>
  <p class="text-muted-foreground">Content</p>
</div>

<!-- Input -->
<input class="w-full px-4 py-2 border border-input rounded-lg focus:ring-2 focus:ring-ring focus:border-transparent transition-all" placeholder="Email">
```

---

## Accessibility

- **Semantic HTML**: Use `<header>`, `<nav>`, `<main>`, `<article>`, `<footer>` — not div soup
- **ARIA**: `aria-label` on icon buttons and nav elements
- **Focus**: `focus:ring-2 focus:ring-ring focus:ring-offset-2` on interactive elements
- **Contrast**: 4.5:1 minimum for normal text

---

## Performance

```html
<!-- Preload fonts -->
<link rel="preload" href="/fonts/inter.woff2" as="font" type="font/woff2" crossorigin>

<!-- Responsive images -->
<img src="img-800.jpg" srcset="img-400.jpg 400w, img-800.jpg 800w, img-1200.jpg 1200w"
     sizes="(max-width: 768px) 100vw, 50vw" alt="Description" loading="lazy">

<!-- Async CSS -->
<link rel="stylesheet" href="styles.css" media="print" onload="this.media='all'">
```

---

## Specificity Rules

| Scenario | Approach |
|----------|----------|
| General styling | Tailwind utility classes |
| Framework overrides (typography, theme) | `!important` on CSS custom properties |
| Layout/spacing | Tailwind utilities (`m-4 p-4 flex`) — never `!important` |
| Theming | CSS custom properties (`--primary`, `--radius`) |

---

## Alternative Frameworks

| Framework | CDN |
|-----------|-----|
| Bootstrap | `bootstrap@5.3.0/dist/css/bootstrap.min.css` + `.../bootstrap.bundle.min.js` |
| Bulma | `bulma@0.9.4/css/bulma.min.css` |
| Foundation | `foundation-sites@6.7.5/dist/css/foundation.min.css` + `.../foundation.min.js` |

---

## References

- [Tailwind CSS](https://tailwindcss.com/docs) | [Flowbite](https://flowbite.com/docs/getting-started/introduction/)
- [WCAG Guidelines](https://www.w3.org/WAI/WCAG21/quickref/) | [MDN Accessibility](https://developer.mozilla.org/en-US/docs/Web/Accessibility)
