# Deploy Flutter App to GitHub Pages

## Quick Start

```powershell
flutter build web --release --base-href "/"
```

## GitHub Actions (Automatic)

The workflow is already configured at `.github/workflows/deploy.yml`:

- Triggers on push to `main` branch or manual dispatch
- Builds Flutter web and deploys to GitHub Pages via `peaceiris/actions-gh-pages@v3`
- Publishes `./build/web` to the `gh-pages` branch

### Setup Steps

1. Push to `main` — workflow runs automatically
2. Go to repository → Settings → Pages
3. Under "Source", select "Deploy from a branch"
4. Select branch: `gh-pages`, folder: `/ (root)`
5. Click Save

## Custom Domain

### 1. Add CNAME file

Create `web/CNAME` (no extension):
```
yourdomain.com
```

Rebuild with base-href `/`:
```powershell
flutter build web --release --base-href "/"
```

### 2. DNS Configuration

**Apex domain (yourdomain.com):**
| Type | Name | Value |
|------|------|-------|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |

**WWW subdomain (www.yourdomain.com):**
| Type | Name | Value |
|------|------|-------|
| CNAME | www | YOUR-USERNAME.github.io |

### 3. Enable in GitHub

1. Repository → Settings → Pages
2. Enter custom domain, save
3. Wait for DNS propagation (24-48 hours)
4. Enable "Enforce HTTPS"

## Manual Deployment

```powershell
flutter build web --release --base-href "/"
npm install -g gh-pages
gh-pages -d build/web
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| 404 on refresh | Add `web/404.html` redirecting to `index.html` |
| Blank page | Check `base-href` matches deployment path |
| Assets not loading | Verify `base-href` and `pubspec.yaml` assets |
| DNS not propagating | Wait 24-48h, check with `nslookup yourdomain.com` |
