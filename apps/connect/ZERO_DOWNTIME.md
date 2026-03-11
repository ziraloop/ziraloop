# Zero-Downtime Deployment for Connect

## Current State: NOT Zero-Downtime

The current deployment has a small window where users can see errors:

```
Problem: Mixed assets during S3 sync
├─ index.html uploaded first (references new JS)
├─ User loads new HTML
└─ User requests new JS chunk → 404 (not uploaded yet)
```

## Solution: Atomic Deployment

### Strategy: Versioned Assets

```
S3 Bucket Structure:
├── v1a2b3c/
│   ├── index.html
│   └── assets/
├── v4d5e6f/          ← New version
│   ├── index.html
│   └── assets/
├── index.html → (copy of v4d5e6f/index.html)  ← Atomic switch
└── assets/ → (not used, all assets versioned)
```

### How It Works

1. **Build** → Create hashed assets
2. **Upload** → Upload to `s3://bucket/v{hash}/`
3. **Atomic Switch** → Copy `v{hash}/index.html` to root
4. **Invalidate** → Only `/index.html` needs invalidation

### Benefits

| Feature | Current | Atomic |
|---------|---------|--------|
| Downtime | ~5-30s | 0s |
| Rollback | Re-deploy | Instant (copy old index.html) |
| Cache hits | Mixed | 100% immutable assets |
| User experience | Potential 404s | Always consistent |

## Implementation

### Option A: Use Atomic Script (Recommended)

```bash
# Replace deploy.sh with atomic version
cp scripts/deploy-atomic.sh scripts/deploy.sh

# Deploy
npm run deploy:dev
```

### Option B: Manual Steps

```bash
# 1. Build with hashed filenames
npm run build

# 2. Upload to version folder
VERSION=$(git rev-parse --short HEAD)
aws s3 sync dist/ "s3://bucket/v${VERSION}/" \
    --cache-control "max-age=31536000,immutable"

# 3. Atomic switch (only index.html)
aws s3 cp "s3://bucket/v${VERSION}/index.html" \
    "s3://bucket/index.html" \
    --cache-control "no-cache"

# 4. Invalidate only index.html
aws cloudfront create-invalidation \
    --distribution-id $DIST_ID \
    --paths "/index.html"
```

## Vite Configuration for Atomic Deploy

Update `vite.config.ts`:

```typescript
export default defineConfig({
  build: {
    // Ensure assets have content hash
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash].[ext]',
      },
    },
  },
})
```

## Rollback Strategy

With atomic deployment, rollback is instant:

```bash
# Rollback to previous version
aws s3 cp "s3://bucket/v{old-version}/index.html" \
    "s3://bucket/index.html"

# Invalidate
aws cloudfront create-invalidation \
    --distribution-id $DIST_ID \
    --paths "/index.html"
```

## Trade-offs

| Aspect | Current | Atomic |
|--------|---------|--------|
| Complexity | Simple | Medium |
| Storage | ~10MB | ~10MB × versions |
| Deploy time | 10s | 15s |
| Rollback time | 5min | 5s |
| User impact | Possible errors | Zero errors |

## Recommendation

**For production:** Use atomic deployment
**For development:** Current method is fine

Switch to atomic when you're ready for production stability.
