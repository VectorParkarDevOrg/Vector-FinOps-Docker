# OptScale White-Labeling Script

A production-ready bash script for white-labeling OptScale deployments.

## Overview

This script automates the complete white-labeling process for OptScale, including:
- Replacing logo and favicon assets
- Updating brand name across the application
- Modifying welcome page elements
- Removing Hystax/OptScale specific content
- Building and deploying the updated UI

## Prerequisites

### Required Dependencies
- **bash** 4.0+
- **jq** - JSON processing
- **sed** - Text manipulation
- **grep** - Pattern matching
- **kubectl** - Kubernetes CLI (for deployment)
- **nerdctl** or **docker** - Container build tool

### Optional Dependencies
- **ImageMagick** (`convert` command) - For favicon generation

### Install Dependencies (Ubuntu/Debian)
```bash
apt-get update
apt-get install -y jq imagemagick
```

## User Input Requirements

### Required Inputs

| Input | Flag | Description |
|-------|------|-------------|
| Brand Name | `-n, --name` | Your brand/product name (replaces "OptScale") |
| Logo SVG | `-l, --logo` | Path to main logo in SVG format |
| Logo PNG | `-p, --logo-png` | Path to logo in PNG format (for PDF exports, emails) |

### Optional Inputs

| Input | Flag | Description | Default |
|-------|------|-------------|---------|
| White Logo SVG | `-w, --logo-white` | Logo for dark backgrounds | Uses main logo |
| Favicon | `-f, --favicon` | Custom favicon.ico file | Generated from PNG |
| Live Demo URL | `-u, --live-demo-url` | External URL for "Live Demo" button | Internal route |
| Brand URL | `-b, --brand-url` | URL for brand link (top-right) | hystax.com |
| Brand Link Text | `-t, --brand-link-text` | Text for brand link | Brand name |

### Feature Flags

| Flag | Description |
|------|-------------|
| `--remove-trusted-by` | Remove "Trusted by" customer logos section |
| `--remove-github-popup` | Remove GitHub star popup notification |
| `--dry-run` | Preview changes without applying them |
| `--skip-build` | Skip Docker image build |
| `--skip-deploy` | Skip Kubernetes deployment |
| `-v, --verbose` | Enable verbose output |

## Usage

### Basic Usage
```bash
./whitelabel.sh -n "MyBrand" -l /path/to/logo.svg -p /path/to/logo.png
```

### Full White-Labeling
```bash
./whitelabel.sh \
    -n "MyBrand" \
    -l /path/to/logo.svg \
    -p /path/to/logo.png \
    -w /path/to/logo_white.svg \
    -f /path/to/favicon.ico \
    -u "https://mybrand.com/book-a-call" \
    -b "https://mybrand.com" \
    -t "MyBrand" \
    --remove-trusted-by \
    --remove-github-popup
```

### Using Configuration File
```bash
./whitelabel.sh -c whitelabel_config.json
```

### Dry Run (Preview Changes)
```bash
./whitelabel.sh -n "MyBrand" -l logo.svg -p logo.png --dry-run
```

### Restore from Backup
```bash
./whitelabel.sh --restore /path/to/backup/whitelabel_20240101_120000
```

## Configuration File Format

Create a JSON file with your branding configuration:

```json
{
    "brand_name": "MyBrand",
    "logo_svg": "/path/to/logo.svg",
    "logo_png": "/path/to/logo.png",
    "logo_white_svg": "/path/to/logo_white.svg",
    "favicon_ico": "/path/to/favicon.ico",
    "live_demo_url": "https://mybrand.com/book-a-call",
    "brand_url": "https://mybrand.com",
    "brand_link_text": "MyBrand",
    "remove_trusted_by": true,
    "remove_github_popup": true
}
```

## Logo Requirements

### Main Logo (SVG)
- Format: SVG (vector)
- Recommended dimensions: Width ~150-200px, Height ~45px
- Used in: Header, login page, welcome page

### Logo PNG
- Format: PNG with transparency
- Recommended dimensions: 150x45px or similar aspect ratio
- Used in: PDF exports, email templates

### White Logo (SVG) - Optional
- Format: SVG (vector)
- White or light-colored version for dark backgrounds
- If not provided, main logo is used

### Favicon
- Format: ICO (multi-resolution) or PNG
- If not provided, generated from logo PNG
- Generated sizes: 64x64, 48x48, 32x32, 16x16

## What Gets Changed

### Files Modified

| File | Changes |
|------|---------|
| `ngui/ui/src/assets/logo/logo.svg` | Main logo |
| `ngui/ui/src/assets/logo/logo_white.svg` | White logo |
| `ngui/ui/src/assets/logo/logo_short_white.svg` | Compact white logo |
| `ngui/ui/src/assets/logo/logo_pdf.png` | PDF export logo |
| `ngui/ui/public/favicon.ico` | Browser favicon |
| `ngui/ui/public/manifest.json` | App name |
| `ngui/ui/index.html` | Page title |
| `ngui/ui/src/translations/en-US/app.json` | Brand name, link text |
| `ngui/ui/src/urls.ts` | Brand URL |
| `ngui/ui/src/components/Greeter/Greeter.tsx` | Welcome page components |
| `ngui/ui/src/components/TopAlertWrapper/TopAlertWrapper.tsx` | GitHub popup |
| `herald/modules/email_generator/images/` | Email logos |

## Backup & Restore

### Automatic Backup
Every run creates a timestamped backup at:
```
/path/to/optscale/backups/whitelabel_YYYYMMDD_HHMMSS/
```

### Backup Contents
- All modified files before changes
- Configuration used (`config.json`)

### Restore Command
```bash
./whitelabel.sh --restore /path/to/backup/whitelabel_YYYYMMDD_HHMMSS
```

## Logging

Logs are saved to:
```
/path/to/optscale/logs/whitelabel_YYYYMMDD_HHMMSS.log
```

## Troubleshooting

### Build Fails - buildctl not found
```bash
export PATH="/root/bin:$PATH"
# Then run the script again
```

### ImageMagick not available
```bash
apt-get install -y imagemagick
# Or provide your own favicon with -f flag
```

### Deployment timeout
```bash
# Check pod status
kubectl get pods | grep ngui
kubectl logs deployment/ngui

# Retry deployment only
./whitelabel.sh --skip-build -n "MyBrand" -l logo.svg -p logo.png
```

### Restore not working
1. Check backup directory exists
2. Ensure all backed up files are present
3. Run with verbose mode: `./whitelabel.sh --restore /path/to/backup -v`

## Examples

### Example 1: Simple Rebranding
```bash
./whitelabel.sh \
    -n "CloudCost" \
    -l ./assets/cloudcost-logo.svg \
    -p ./assets/cloudcost-logo.png
```

### Example 2: Full Enterprise White-Label
```bash
./whitelabel.sh \
    -n "Acme Cloud Manager" \
    -l ./branding/acme-logo.svg \
    -p ./branding/acme-logo.png \
    -w ./branding/acme-logo-white.svg \
    -f ./branding/acme-favicon.ico \
    -u "https://acme.com/schedule-demo" \
    -b "https://acme.com/cloud-manager" \
    -t "Acme" \
    --remove-trusted-by \
    --remove-github-popup \
    -v
```

### Example 3: CI/CD Pipeline
```bash
# Use config file in CI/CD
./whitelabel.sh -c /configs/whitelabel.json --skip-deploy

# Deploy separately
kubectl rollout restart deployment/ngui
```

## License

This script is part of the OptScale project.
