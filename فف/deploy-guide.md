# Deploy Flutter App to GitHub Pages with Custom Domain

## Prerequisites
- Git installed on your computer
- GitHub account
- Custom domain (e.g., yourdomain.com)

## Step 1: Build Your Flutter Web App

```powershell
cd d:\Programing\flutter\StudyFlowPdf
flutter build web --release --base-href "/StudyFlowPdf/"
```

**Note:** Replace `/StudyFlowPdf/` with `/your-repo-name/` or use `/` if using a custom domain.

## Step 2: Initialize Git Repository (if not already done)

```powershell
cd d:\Programing\flutter\StudyFlowPdf
git init
git add .
git commit -m "Initial commit"
```

## Step 3: Create GitHub Repository

1. Go to https://github.com and log in
2. Click "New repository" (the + icon in top right)
3. Name it `StudyFlowPdf` (or any name you prefer)
4. Keep it public (required for free GitHub Pages)
5. Don't initialize with README (we already have code)
6. Click "Create repository"

## Step 4: Push Code to GitHub

```powershell
git remote add origin https://github.com/YOUR-USERNAME/StudyFlowPdf.git
git branch -M main
git push -u origin main
```

Replace `YOUR-USERNAME` with your actual GitHub username.

## Step 5: Deploy to GitHub Pages

### Option A: Using GitHub Actions (Recommended - Automatic)

1. Create `.github/workflows/deploy.yml` in your project:

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.10.7'
          channel: 'stable'
      
      - name: Install dependencies
        run: flutter pub get
      
      - name: Build web
        run: flutter build web --release --base-href "/StudyFlowPdf/"
      
      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./build/web
```

2. Push this file to GitHub
3. Go to your repository → Settings → Pages
4. Under "Source", select "Deploy from a branch"
5. Select branch: `gh-pages` and folder: `/ (root)`
6. Click Save

### Option B: Manual Deployment

```powershell
# Build the app
flutter build web --release --base-href "/StudyFlowPdf/"

# Install gh-pages tool (one time)
npm install -g gh-pages

# Deploy to gh-pages branch
gh-pages -d build/web
```

OR manually:

```powershell
# Build the app
flutter build web --release --base-href "/StudyFlowPdf/"

# Create gh-pages branch
git checkout --orphan gh-pages
git rm -rf .
Copy-Item -Path build\web\* -Destination . -Recurse
git add .
git commit -m "Deploy to GitHub Pages"
git push origin gh-pages
git checkout main
```

## Step 6: Configure Custom Domain

### A. Add CNAME file to your project

1. Create a file named `CNAME` in `web/` folder (no extension):
```
yourdomain.com
```

2. Rebuild and redeploy:
```powershell
flutter build web --release --base-href "/"
git add .
git commit -m "Add custom domain"
git push
```

### B. Configure DNS Settings

In your domain provider (GoDaddy, Namecheap, Cloudflare, etc.):

**For apex domain (yourdomain.com):**
- Type: A
- Name: @ (or leave empty)
- Value: 185.199.108.153
- Add three more A records with:
  - 185.199.109.153
  - 185.199.110.153
  - 185.199.111.153

**For www subdomain (www.yourdomain.com):**
- Type: CNAME
- Name: www
- Value: YOUR-USERNAME.github.io

### C. Enable Custom Domain in GitHub

1. Go to your repository → Settings → Pages
2. Under "Custom domain", enter: `yourdomain.com`
3. Click Save
4. Wait for DNS check (can take up to 24-48 hours)
5. Enable "Enforce HTTPS" (after DNS propagates)

## Step 7: Update base-href for Custom Domain

When using a custom domain, rebuild with:
```powershell
flutter build web --release --base-href "/"
```

## Testing Your Deployment

- **GitHub Pages URL**: `https://YOUR-USERNAME.github.io/StudyFlowPdf/`
- **Custom Domain URL**: `https://yourdomain.com`

## Common Issues & Solutions

### Issue 1: 404 Error on Page Refresh
Add `.htaccess` or configure routing. For GitHub Pages, create `web/404.html` that redirects to `index.html`.

### Issue 2: Blank Page
- Check browser console for errors
- Verify `base-href` is correct
- Check if files are loading from correct path

### Issue 3: Assets Not Loading
- Ensure `base-href` matches your deployment path
- Check that assets are included in `pubspec.yaml`

### Issue 4: DNS Not Propagating
- Wait 24-48 hours
- Check DNS with: `nslookup yourdomain.com`
- Clear browser cache

## Maintenance

To update your app:
```powershell
# Make changes to your code
git add .
git commit -m "Update description"
git push

# If using GitHub Actions, it will auto-deploy
# If manual, run: flutter build web --release && gh-pages -d build/web
```

## Resources

- [Flutter Web Deployment](https://docs.flutter.dev/deployment/web)
- [GitHub Pages Documentation](https://docs.github.com/en/pages)
- [Custom Domain Setup](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site)
