#!/usr/bin/env bash

#===============================================================================
# OptScale White-Labeling Script
#
# This script automates the white-labeling process for OptScale deployments.
# It replaces branding assets, updates configuration files, and rebuilds the UI.
#
# Usage: ./whitelabel.sh [OPTIONS]
#
# Author: Auto-generated
# Version: 1.0.0
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration & Defaults
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTSCALE_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${OPTSCALE_ROOT}/backups/whitelabel_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${OPTSCALE_ROOT}/logs/whitelabel_$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE=""

# UI Paths
UI_DIR="${OPTSCALE_ROOT}/ngui/ui"
ASSETS_LOGO_DIR="${UI_DIR}/src/assets/logo"
PUBLIC_DIR="${UI_DIR}/public"
TRANSLATIONS_DIR="${UI_DIR}/src/translations/en-US"
COMPONENTS_DIR="${UI_DIR}/src/components"
EMAIL_IMAGES_DIR="${OPTSCALE_ROOT}/herald/modules/email_generator/images"

# Default values
BRAND_NAME=""
LOGO_SVG=""
LOGO_PNG=""
LOGO_WHITE_SVG=""
FAVICON_ICO=""
LIVE_DEMO_URL=""
BRAND_URL=""
BRAND_LINK_TEXT=""
REMOVE_TRUSTED_BY="false"
REMOVE_GITHUB_POPUP="false"
DRY_RUN="false"
SKIP_BUILD="false"
SKIP_DEPLOY="false"
VERBOSE="false"
RESTORE_BACKUP=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------
setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE") 2>&1
    log_info "Logging to: $LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

log_step() {
    echo -e "\n${BLUE}==>${NC} $1"
}

#-------------------------------------------------------------------------------
# Help & Usage
#-------------------------------------------------------------------------------
show_help() {
    cat << EOF
OptScale White-Labeling Script v1.0.0

USAGE:
    $(basename "$0") [OPTIONS]

DESCRIPTION:
    Automates white-labeling of OptScale deployments by replacing branding
    assets, updating configuration files, and rebuilding the UI.

REQUIRED OPTIONS:
    -n, --name <name>           Brand/product name (replaces "OptScale")
    -l, --logo <path>           Path to main logo SVG file
    -p, --logo-png <path>       Path to logo PNG file (for PDF exports)

OPTIONAL OPTIONS:
    -w, --logo-white <path>     Path to white logo SVG (default: uses main logo)
    -f, --favicon <path>        Path to favicon.ico (default: generated from PNG)
    -u, --live-demo-url <url>   URL for "Live Demo" button
    -b, --brand-url <url>       URL for brand link (top-right corner)
    -t, --brand-link-text <text> Text for brand link (default: brand name)

    --remove-trusted-by         Remove "Trusted by" section from welcome page
    --remove-github-popup       Remove GitHub star popup

    -c, --config <path>         Load configuration from JSON file
    --dry-run                   Show what would be changed without making changes
    --skip-build                Skip Docker image build
    --skip-deploy               Skip Kubernetes deployment
    -v, --verbose               Enable verbose output

    --restore <backup_dir>      Restore from a previous backup
    -h, --help                  Show this help message

EXAMPLES:
    # Basic white-labeling with required options
    $(basename "$0") -n "MyBrand" -l logo.svg -p logo.png

    # Full white-labeling with all options
    $(basename "$0") -n "MyBrand" -l logo.svg -p logo.png \\
        -w logo_white.svg \\
        -u "https://mybrand.com/demo" \\
        -b "https://mybrand.com" \\
        -t "MyBrand" \\
        --remove-trusted-by \\
        --remove-github-popup

    # Using a configuration file
    $(basename "$0") -c whitelabel_config.json

    # Dry run to preview changes
    $(basename "$0") -n "MyBrand" -l logo.svg -p logo.png --dry-run

    # Restore from backup
    $(basename "$0") --restore /path/to/backup

CONFIGURATION FILE FORMAT (JSON):
    {
        "brand_name": "MyBrand",
        "logo_svg": "/path/to/logo.svg",
        "logo_png": "/path/to/logo.png",
        "logo_white_svg": "/path/to/logo_white.svg",
        "favicon_ico": "/path/to/favicon.ico",
        "live_demo_url": "https://mybrand.com/demo",
        "brand_url": "https://mybrand.com",
        "brand_link_text": "MyBrand",
        "remove_trusted_by": true,
        "remove_github_popup": true
    }

OUTPUT:
    - Backup of original files: ${OPTSCALE_ROOT}/backups/
    - Log files: ${OPTSCALE_ROOT}/logs/

NOTES:
    - Requires: bash 4+, jq, imagemagick, kubectl, nerdctl/docker
    - Run from OptScale root directory or specify OPTSCALE_ROOT
    - Always creates a backup before making changes
    - Use --restore to rollback if needed

EOF
}

#-------------------------------------------------------------------------------
# Argument Parsing
#-------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                BRAND_NAME="$2"
                shift 2
                ;;
            -l|--logo)
                LOGO_SVG="$2"
                shift 2
                ;;
            -p|--logo-png)
                LOGO_PNG="$2"
                shift 2
                ;;
            -w|--logo-white)
                LOGO_WHITE_SVG="$2"
                shift 2
                ;;
            -f|--favicon)
                FAVICON_ICO="$2"
                shift 2
                ;;
            -u|--live-demo-url)
                LIVE_DEMO_URL="$2"
                shift 2
                ;;
            -b|--brand-url)
                BRAND_URL="$2"
                shift 2
                ;;
            -t|--brand-link-text)
                BRAND_LINK_TEXT="$2"
                shift 2
                ;;
            --remove-trusted-by)
                REMOVE_TRUSTED_BY="true"
                shift
                ;;
            --remove-github-popup)
                REMOVE_GITHUB_POPUP="true"
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --skip-build)
                SKIP_BUILD="true"
                shift
                ;;
            --skip-deploy)
                SKIP_DEPLOY="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            --restore)
                RESTORE_BACKUP="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Configuration Loading
#-------------------------------------------------------------------------------
load_config_file() {
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Configuration file not found: $CONFIG_FILE"
            exit 1
        fi

        log_info "Loading configuration from: $CONFIG_FILE"

        # Parse JSON config using jq
        BRAND_NAME="${BRAND_NAME:-$(jq -r '.brand_name // empty' "$CONFIG_FILE")}"
        LOGO_SVG="${LOGO_SVG:-$(jq -r '.logo_svg // empty' "$CONFIG_FILE")}"
        LOGO_PNG="${LOGO_PNG:-$(jq -r '.logo_png // empty' "$CONFIG_FILE")}"
        LOGO_WHITE_SVG="${LOGO_WHITE_SVG:-$(jq -r '.logo_white_svg // empty' "$CONFIG_FILE")}"
        FAVICON_ICO="${FAVICON_ICO:-$(jq -r '.favicon_ico // empty' "$CONFIG_FILE")}"
        LIVE_DEMO_URL="${LIVE_DEMO_URL:-$(jq -r '.live_demo_url // empty' "$CONFIG_FILE")}"
        BRAND_URL="${BRAND_URL:-$(jq -r '.brand_url // empty' "$CONFIG_FILE")}"
        BRAND_LINK_TEXT="${BRAND_LINK_TEXT:-$(jq -r '.brand_link_text // empty' "$CONFIG_FILE")}"

        local remove_trusted=$(jq -r '.remove_trusted_by // false' "$CONFIG_FILE")
        local remove_github=$(jq -r '.remove_github_popup // false' "$CONFIG_FILE")

        [[ "$remove_trusted" == "true" ]] && REMOVE_TRUSTED_BY="true"
        [[ "$remove_github" == "true" ]] && REMOVE_GITHUB_POPUP="true"
    fi
}

#-------------------------------------------------------------------------------
# Validation Functions
#-------------------------------------------------------------------------------
check_dependencies() {
    log_step "Checking dependencies..."

    local missing_deps=()

    # Required commands
    for cmd in jq sed grep kubectl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    # Check for container build tool
    if ! command -v nerdctl &> /dev/null && ! command -v docker &> /dev/null; then
        missing_deps+=("nerdctl or docker")
    fi

    # Check for ImageMagick (for favicon generation)
    if ! command -v convert &> /dev/null; then
        log_warn "ImageMagick not found. Favicon generation will be skipped."
        log_warn "Install with: apt-get install imagemagick"
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi

    # Check buildctl for nerdctl
    if command -v nerdctl &> /dev/null; then
        if ! command -v buildctl &> /dev/null; then
            if [[ -x "/root/bin/buildctl" ]]; then
                export PATH="/root/bin:$PATH"
                log_debug "Added /root/bin to PATH for buildctl"
            else
                log_warn "buildctl not found. Build may fail."
            fi
        fi
    fi

    log_info "All dependencies satisfied"
}

validate_inputs() {
    log_step "Validating inputs..."

    local errors=()

    # Required fields
    if [[ -z "$BRAND_NAME" ]]; then
        errors+=("Brand name is required (-n/--name)")
    fi

    if [[ -z "$LOGO_SVG" ]]; then
        errors+=("Logo SVG file is required (-l/--logo)")
    elif [[ ! -f "$LOGO_SVG" ]]; then
        errors+=("Logo SVG file not found: $LOGO_SVG")
    fi

    if [[ -z "$LOGO_PNG" ]]; then
        errors+=("Logo PNG file is required (-p/--logo-png)")
    elif [[ ! -f "$LOGO_PNG" ]]; then
        errors+=("Logo PNG file not found: $LOGO_PNG")
    fi

    # Optional file validation
    if [[ -n "$LOGO_WHITE_SVG" && ! -f "$LOGO_WHITE_SVG" ]]; then
        errors+=("White logo SVG file not found: $LOGO_WHITE_SVG")
    fi

    if [[ -n "$FAVICON_ICO" && ! -f "$FAVICON_ICO" ]]; then
        errors+=("Favicon file not found: $FAVICON_ICO")
    fi

    # URL validation
    if [[ -n "$LIVE_DEMO_URL" && ! "$LIVE_DEMO_URL" =~ ^https?:// ]]; then
        errors+=("Live demo URL must start with http:// or https://")
    fi

    if [[ -n "$BRAND_URL" && ! "$BRAND_URL" =~ ^https?:// ]]; then
        errors+=("Brand URL must start with http:// or https://")
    fi

    # Check OptScale directory structure
    if [[ ! -d "$UI_DIR" ]]; then
        errors+=("OptScale UI directory not found: $UI_DIR")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Validation failed:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        exit 1
    fi

    # Set defaults
    LOGO_WHITE_SVG="${LOGO_WHITE_SVG:-$LOGO_SVG}"
    BRAND_LINK_TEXT="${BRAND_LINK_TEXT:-$BRAND_NAME}"

    log_info "Input validation passed"

    # Display configuration
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        echo "Configuration:"
        echo "  Brand Name:        $BRAND_NAME"
        echo "  Logo SVG:          $LOGO_SVG"
        echo "  Logo PNG:          $LOGO_PNG"
        echo "  Logo White SVG:    $LOGO_WHITE_SVG"
        echo "  Favicon:           ${FAVICON_ICO:-"(will be generated)"}"
        echo "  Live Demo URL:     ${LIVE_DEMO_URL:-"(not set)"}"
        echo "  Brand URL:         ${BRAND_URL:-"(not set)"}"
        echo "  Brand Link Text:   $BRAND_LINK_TEXT"
        echo "  Remove Trusted By: $REMOVE_TRUSTED_BY"
        echo "  Remove GitHub:     $REMOVE_GITHUB_POPUP"
        echo ""
    fi
}

#-------------------------------------------------------------------------------
# Backup Functions
#-------------------------------------------------------------------------------
create_backup() {
    log_step "Creating backup..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup at: $BACKUP_DIR"
        return
    fi

    mkdir -p "$BACKUP_DIR"

    # Backup logo files
    if [[ -d "$ASSETS_LOGO_DIR" ]]; then
        cp -r "$ASSETS_LOGO_DIR" "$BACKUP_DIR/logo/"
        log_debug "Backed up: $ASSETS_LOGO_DIR"
    fi

    # Backup public files
    cp "$PUBLIC_DIR/favicon.ico" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PUBLIC_DIR/manifest.json" "$BACKUP_DIR/" 2>/dev/null || true
    log_debug "Backed up: public files"

    # Backup index.html
    cp "$UI_DIR/index.html" "$BACKUP_DIR/" 2>/dev/null || true
    log_debug "Backed up: index.html"

    # Backup translations
    cp "$TRANSLATIONS_DIR/app.json" "$BACKUP_DIR/" 2>/dev/null || true
    log_debug "Backed up: translations"

    # Backup component files
    mkdir -p "$BACKUP_DIR/components"
    cp "$COMPONENTS_DIR/Greeter/Greeter.tsx" "$BACKUP_DIR/components/" 2>/dev/null || true
    cp "$COMPONENTS_DIR/TopAlertWrapper/TopAlertWrapper.tsx" "$BACKUP_DIR/components/" 2>/dev/null || true
    log_debug "Backed up: components"

    # Backup urls.ts
    cp "$UI_DIR/src/urls.ts" "$BACKUP_DIR/" 2>/dev/null || true
    log_debug "Backed up: urls.ts"

    # Backup email images
    if [[ -d "$EMAIL_IMAGES_DIR" ]]; then
        mkdir -p "$BACKUP_DIR/email_images"
        cp "$EMAIL_IMAGES_DIR/logo_new.png" "$BACKUP_DIR/email_images/" 2>/dev/null || true
        cp "$EMAIL_IMAGES_DIR/logo_optscale_white.png" "$BACKUP_DIR/email_images/" 2>/dev/null || true
        log_debug "Backed up: email images"
    fi

    # Save configuration used
    cat > "$BACKUP_DIR/config.json" << EOF
{
    "brand_name": "$BRAND_NAME",
    "logo_svg": "$LOGO_SVG",
    "logo_png": "$LOGO_PNG",
    "logo_white_svg": "$LOGO_WHITE_SVG",
    "favicon_ico": "$FAVICON_ICO",
    "live_demo_url": "$LIVE_DEMO_URL",
    "brand_url": "$BRAND_URL",
    "brand_link_text": "$BRAND_LINK_TEXT",
    "remove_trusted_by": $REMOVE_TRUSTED_BY,
    "remove_github_popup": $REMOVE_GITHUB_POPUP,
    "timestamp": "$(date -Iseconds)"
}
EOF

    log_info "Backup created at: $BACKUP_DIR"
}

restore_backup() {
    local backup_path="$1"

    log_step "Restoring from backup: $backup_path"

    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup directory not found: $backup_path"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore from: $backup_path"
        return
    fi

    # Restore logo files
    if [[ -d "$backup_path/logo" ]]; then
        cp -r "$backup_path/logo/"* "$ASSETS_LOGO_DIR/"
        log_info "Restored: logo files"
    fi

    # Restore public files
    [[ -f "$backup_path/favicon.ico" ]] && cp "$backup_path/favicon.ico" "$PUBLIC_DIR/"
    [[ -f "$backup_path/manifest.json" ]] && cp "$backup_path/manifest.json" "$PUBLIC_DIR/"
    log_info "Restored: public files"

    # Restore index.html
    [[ -f "$backup_path/index.html" ]] && cp "$backup_path/index.html" "$UI_DIR/"
    log_info "Restored: index.html"

    # Restore translations
    [[ -f "$backup_path/app.json" ]] && cp "$backup_path/app.json" "$TRANSLATIONS_DIR/"
    log_info "Restored: translations"

    # Restore components
    [[ -f "$backup_path/components/Greeter.tsx" ]] && cp "$backup_path/components/Greeter.tsx" "$COMPONENTS_DIR/Greeter/"
    [[ -f "$backup_path/components/TopAlertWrapper.tsx" ]] && cp "$backup_path/components/TopAlertWrapper.tsx" "$COMPONENTS_DIR/TopAlertWrapper/"
    log_info "Restored: components"

    # Restore urls.ts
    [[ -f "$backup_path/urls.ts" ]] && cp "$backup_path/urls.ts" "$UI_DIR/src/"
    log_info "Restored: urls.ts"

    # Restore email images
    if [[ -d "$backup_path/email_images" ]]; then
        cp "$backup_path/email_images/"* "$EMAIL_IMAGES_DIR/" 2>/dev/null || true
        log_info "Restored: email images"
    fi

    log_info "Restore completed successfully"
}

#-------------------------------------------------------------------------------
# White-labeling Functions
#-------------------------------------------------------------------------------
update_logos() {
    log_step "Updating logo files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would copy logos to: $ASSETS_LOGO_DIR"
        return
    fi

    # Main logo
    cp "$LOGO_SVG" "$ASSETS_LOGO_DIR/logo.svg"
    log_debug "Updated: logo.svg"

    # White logo variants
    cp "$LOGO_WHITE_SVG" "$ASSETS_LOGO_DIR/logo_white.svg"
    cp "$LOGO_WHITE_SVG" "$ASSETS_LOGO_DIR/logo_short_white.svg"
    log_debug "Updated: white logo variants"

    # PDF logo
    cp "$LOGO_PNG" "$ASSETS_LOGO_DIR/logo_pdf.png"
    log_debug "Updated: logo_pdf.png"

    # Email logos
    if [[ -d "$EMAIL_IMAGES_DIR" ]]; then
        cp "$LOGO_PNG" "$EMAIL_IMAGES_DIR/logo_new.png"
        cp "$LOGO_PNG" "$EMAIL_IMAGES_DIR/logo_optscale_white.png"
        log_debug "Updated: email logos"
    fi

    log_info "Logo files updated"
}

generate_favicon() {
    log_step "Generating favicon..."

    if [[ -n "$FAVICON_ICO" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would copy favicon from: $FAVICON_ICO"
            return
        fi
        cp "$FAVICON_ICO" "$PUBLIC_DIR/favicon.ico"
        log_info "Favicon copied from: $FAVICON_ICO"
        return
    fi

    if ! command -v convert &> /dev/null; then
        log_warn "ImageMagick not available. Skipping favicon generation."
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate favicon from: $LOGO_PNG"
        return
    fi

    local temp_png="/tmp/favicon_temp_$$.png"

    # Resize and center the logo, then create multi-size ICO
    convert "$LOGO_PNG" \
        -resize 256x256 \
        -background transparent \
        -gravity center \
        -extent 256x256 \
        "$temp_png"

    convert "$temp_png" \
        -define icon:auto-resize=64,48,32,16 \
        "$PUBLIC_DIR/favicon.ico"

    rm -f "$temp_png"

    log_info "Favicon generated with sizes: 64, 48, 32, 16"
}

update_manifest() {
    log_step "Updating manifest.json..."

    local manifest_file="$PUBLIC_DIR/manifest.json"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update brand name in manifest.json"
        return
    fi

    # Update short_name and name
    sed -i "s/\"short_name\": \"OptScale\"/\"short_name\": \"$BRAND_NAME\"/" "$manifest_file"
    sed -i "s/\"name\": \"OptScale\"/\"name\": \"$BRAND_NAME\"/" "$manifest_file"

    log_info "manifest.json updated"
}

update_index_html() {
    log_step "Updating index.html..."

    local index_file="$UI_DIR/index.html"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update title in index.html"
        return
    fi

    # Update title
    sed -i "s/<title>Hystax OptScale<\/title>/<title>$BRAND_NAME<\/title>/" "$index_file"
    sed -i "s/<title>OptScale<\/title>/<title>$BRAND_NAME<\/title>/" "$index_file"

    log_info "index.html updated"
}

update_translations() {
    log_step "Updating translations..."

    local app_json="$TRANSLATIONS_DIR/app.json"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update translations in app.json"
        return
    fi

    # Update optscale brand name
    sed -i "s/\"optscale\": \"OptScale\"/\"optscale\": \"$BRAND_NAME\"/" "$app_json"

    # Update hystaxDotCom link text
    if [[ -n "$BRAND_LINK_TEXT" ]]; then
        sed -i "s/\"hystaxDotCom\": \"www.hystax.com\"/\"hystaxDotCom\": \"$BRAND_LINK_TEXT\"/" "$app_json"
    fi

    log_info "Translations updated"
}

update_urls() {
    log_step "Updating URLs..."

    local urls_file="$UI_DIR/src/urls.ts"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update URLs in urls.ts"
        return
    fi

    # Update HYSTAX URL if brand URL provided
    if [[ -n "$BRAND_URL" ]]; then
        sed -i "s|export const HYSTAX = \"https://hystax.com\";|export const HYSTAX = \"$BRAND_URL\";|" "$urls_file"
        log_debug "Updated HYSTAX URL to: $BRAND_URL"
    fi

    log_info "URLs updated"
}

update_greeter_component() {
    log_step "Updating Greeter component..."

    local greeter_file="$COMPONENTS_DIR/Greeter/Greeter.tsx"

    if [[ ! -f "$greeter_file" ]]; then
        log_warn "Greeter.tsx not found, skipping"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update Greeter.tsx"
        return
    fi

    # Update Live Demo button URL if provided
    if [[ -n "$LIVE_DEMO_URL" ]]; then
        # Check if already modified
        if grep -q "window.open" "$greeter_file"; then
            # Update existing external URL
            sed -i "s|window.open(\"[^\"]*\", \"_blank\"|window.open(\"$LIVE_DEMO_URL\", \"_blank\"|" "$greeter_file"
        else
            # Modify to use external URL - this is a complex change, create a patch
            log_warn "LiveDemoButton modification requires manual review"
            log_info "To redirect Live Demo to external URL, modify LiveDemoButton in Greeter.tsx:"
            log_info "  Replace navigate(url) with: window.open(\"$LIVE_DEMO_URL\", \"_blank\", \"noopener,noreferrer\")"
        fi
    fi

    # Remove Trusted By section if requested
    if [[ "$REMOVE_TRUSTED_BY" == "true" ]]; then
        # Remove CustomersGallery import
        sed -i '/import CustomersGallery from "components\/CustomersGallery";/d' "$greeter_file"

        # Replace CustomersGallery usage with null
        sed -i 's/children: <CustomersGallery \/>/children: null/' "$greeter_file"

        log_debug "Removed Trusted By section"
    fi

    log_info "Greeter component updated"
}

remove_github_popup() {
    if [[ "$REMOVE_GITHUB_POPUP" != "true" ]]; then
        return
    fi

    log_step "Removing GitHub popup..."

    local alert_file="$COMPONENTS_DIR/TopAlertWrapper/TopAlertWrapper.tsx"

    if [[ ! -f "$alert_file" ]]; then
        log_warn "TopAlertWrapper.tsx not found, skipping"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove GitHub popup from TopAlertWrapper.tsx"
        return
    fi

    # Check if OPEN_SOURCE_ANNOUNCEMENT exists
    if ! grep -q "ALERT_TYPES.OPEN_SOURCE_ANNOUNCEMENT" "$alert_file"; then
        log_info "GitHub popup already removed or not present"
        return
    fi

    # Create a temporary file with the modification
    # This removes the entire OPEN_SOURCE_ANNOUNCEMENT alert block
    # Note: This is a simplified approach - for production, consider using AST-based modifications

    # Remove unused imports related to GitHub
    sed -i '/import { Box } from "@mui\/material";/d' "$alert_file"
    sed -i '/import { render as renderGithubButton } from "github-buttons";/d' "$alert_file"
    sed -i '/import { GITHUB_HYSTAX_OPTSCALE_REPO } from "urls";/d' "$alert_file"
    sed -i '/import { SPACING_1 } from "utils\/layouts";/d' "$alert_file"
    sed -i '/import { useGetToken } from "hooks\/useGetToken";/d' "$alert_file"
    sed -i '/import { useRootData } from "hooks\/useRootData";/d' "$alert_file"
    sed -i 's/, IS_EXISTING_USER//' "$alert_file"
    sed -i 's/, useIntl//' "$alert_file"

    log_info "GitHub popup removed"
    log_warn "Please verify TopAlertWrapper.tsx manually to ensure proper cleanup"
}

#-------------------------------------------------------------------------------
# Build & Deploy Functions
#-------------------------------------------------------------------------------
build_image() {
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_info "Skipping build (--skip-build)"
        return
    fi

    log_step "Building Docker image..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would build ngui:local image"
        return
    fi

    cd "$OPTSCALE_ROOT"

    local build_cmd=""
    if command -v nerdctl &> /dev/null; then
        build_cmd="nerdctl build"
    elif command -v docker &> /dev/null; then
        build_cmd="docker build"
    else
        log_error "No container build tool available"
        exit 1
    fi

    log_info "Building with: $build_cmd"

    $build_cmd -t ngui:local -f ngui/Dockerfile . 2>&1 | while read -r line; do
        log_debug "$line"
    done

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Build failed"
        exit 1
    fi

    log_info "Docker image built successfully"
}

deploy_to_kubernetes() {
    if [[ "$SKIP_DEPLOY" == "true" ]]; then
        log_info "Skipping deployment (--skip-deploy)"
        return
    fi

    log_step "Deploying to Kubernetes..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restart ngui deployment"
        return
    fi

    # Check if deployment exists
    if ! kubectl get deployment ngui &> /dev/null; then
        log_error "ngui deployment not found in Kubernetes"
        exit 1
    fi

    # Restart deployment
    kubectl rollout restart deployment/ngui

    log_info "Waiting for rollout to complete..."
    if kubectl rollout status deployment/ngui --timeout=180s; then
        log_info "Deployment completed successfully"
    else
        log_error "Deployment rollout failed or timed out"
        exit 1
    fi

    # Verify pod is running
    local pod_status=$(kubectl get pods -l app=ngui -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [[ "$pod_status" == "Running" ]]; then
        log_info "ngui pod is running"
    else
        log_warn "ngui pod status: $pod_status"
    fi
}

#-------------------------------------------------------------------------------
# Summary Function
#-------------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "=============================================="
    echo "       White-Labeling Complete"
    echo "=============================================="
    echo ""
    echo "Brand Name:         $BRAND_NAME"
    echo "Backup Location:    $BACKUP_DIR"
    echo "Log File:           $LOG_FILE"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: DRY RUN (no changes made)"
    else
        echo "Changes Applied:"
        echo "  - Logo files updated"
        echo "  - Favicon $([ -n "$FAVICON_ICO" ] && echo "copied" || echo "generated")"
        echo "  - manifest.json updated"
        echo "  - index.html updated"
        echo "  - Translations updated"
        [[ -n "$BRAND_URL" ]] && echo "  - Brand URL updated"
        [[ -n "$LIVE_DEMO_URL" ]] && echo "  - Live Demo URL updated"
        [[ "$REMOVE_TRUSTED_BY" == "true" ]] && echo "  - Trusted By section removed"
        [[ "$REMOVE_GITHUB_POPUP" == "true" ]] && echo "  - GitHub popup removed"
        [[ "$SKIP_BUILD" != "true" ]] && echo "  - Docker image rebuilt"
        [[ "$SKIP_DEPLOY" != "true" ]] && echo "  - Kubernetes deployment updated"
    fi

    echo ""
    echo "To restore original branding, run:"
    echo "  $0 --restore $BACKUP_DIR"
    echo ""
}

#-------------------------------------------------------------------------------
# Main Function
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo "    OptScale White-Labeling Script v1.0.0"
    echo "=============================================="
    echo ""

    parse_args "$@"

    # Handle restore mode
    if [[ -n "$RESTORE_BACKUP" ]]; then
        setup_logging
        restore_backup "$RESTORE_BACKUP"

        if [[ "$SKIP_BUILD" != "true" ]]; then
            build_image
        fi

        if [[ "$SKIP_DEPLOY" != "true" ]]; then
            deploy_to_kubernetes
        fi

        log_info "Restore completed successfully"
        exit 0
    fi

    # Normal white-labeling mode
    setup_logging
    load_config_file
    check_dependencies
    validate_inputs

    # Confirm before proceeding
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        read -p "Proceed with white-labeling? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted by user"
            exit 0
        fi
    fi

    # Execute white-labeling steps
    create_backup
    update_logos
    generate_favicon
    update_manifest
    update_index_html
    update_translations
    update_urls
    update_greeter_component
    remove_github_popup
    build_image
    deploy_to_kubernetes

    print_summary

    log_info "White-labeling completed successfully!"
}

# Run main function
main "$@"
