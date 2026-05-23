# Change the website & app logo

## Quick steps

1. Get your **official** Dolce & Gabbana logo from brand/IT (PNG or SVG).
2. Replace these files in this folder:

| File | Used for |
|------|----------|
| **`logo.svg`** | Login page, manager header, BA header, browser tab (SVG) |
| **`icon-192.png`** | Optional — better iPhone home-screen icon (192×192) |
| **`icon-512.png`** | Optional — add to `manifest.webmanifest` if you use PNGs |

3. **PNG tips:** square image, logo centered with padding; export at exact pixel sizes.
4. Push to GitHub (Vercel redeploys automatically).
5. On phones that already installed the app: delete the old home-screen icon → **Add to Home Screen** again.

## One file only?

Replacing **`logo.svg`** updates the login page, manager header, BA header, browser tab, and PWA (SVG). For sharper iPhone icons, add PNGs later.

## Do not rename paths

Keep filenames `logo.svg`, `icon-192.png`, `icon-512.png` unless you also update `manifest.webmanifest` and the `<link rel="icon">` tags in `index.html`, `ba.html`, and `manager.html`.
