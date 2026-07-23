#!/usr/bin/env bash

###############################################################################
# Debian Package Template
# Build Script
###############################################################################

set -e

###############################################################################
# Load Configuration
###############################################################################

if [ ! -f "Package.conf" ]; then
    echo "ERROR: Package.conf not found."
    exit 1
fi

source Package.conf

###############################################################################
# Colors
###############################################################################

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[ OK ]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
}


###############################################################################
# Check Build Dependencies
###############################################################################

info "Checking build dependencies..."

BUILD_DEPENDENCIES=(
    "dpkg-deb:dpkg"
    "lintian:lintian"
    "desktop-file-validate:desktop-file-utils"
    "appstreamcli:appstream"
    "update-mime-database:shared-mime-info"
)

MISSING_DEPENDENCIES=()

for DEP in "${BUILD_DEPENDENCIES[@]}"
do
    COMMAND="${DEP%%:*}"
    PACKAGE="${DEP##*:}"

    if ! command -v "$COMMAND" >/dev/null 2>&1
    then
        MISSING_DEPENDENCIES+=("$PACKAGE")
    fi
done

if [ ${#MISSING_DEPENDENCIES[@]} -ne 0 ]
then
    warning "Missing build dependencies:"

    for DEP in "${MISSING_DEPENDENCIES[@]}"
    do
        echo "  - $DEP"
    done

    echo

    read -r -p "Install missing build dependencies? [Y/n] " ANSWER

    case "$ANSWER" in
        n|N)
            error "Cannot continue without required build tools."
            exit 1
            ;;
        *)
            info "Installing build dependencies..."

            sudo apt update
            sudo apt install -y "${MISSING_DEPENDENCIES[@]}"

            success "Build dependencies installed."
            ;;
    esac
fi

success "Build dependencies available."

###############################################################################
# Banner
###############################################################################

echo
echo "=================================================="
echo " Debian Package Template"
echo " Build Script"
echo "=================================================="
echo

###############################################################################
# Check Required Files
###############################################################################

info "Checking project..."

REQUIRED=(
    "DEBIAN/control"
    "README.md"
    "LICENSE.md"
    "usr/bin/debian-package-template"
    "usr/share/applications/debian-package-template.desktop"
    "usr/share/metainfo/io.github.johnlogostini.Debian_Package_Template.metainfo.xml"
    "usr/lib/debian-package-template/dpt"
)

for FILE in "${REQUIRED[@]}"
do
    if [ ! -e "$FILE" ]; then
        error "Missing $FILE"
        exit 1
    fi
done

success "Project looks good."

###############################################################################
# Permissions
###############################################################################

info "Setting executable permissions..."

chmod 755 Build.sh

chmod 755 \
    usr/bin/debian-package-template \
    usr/lib/debian-package-template/dpt \
    DEBIAN/postinst \
    DEBIAN/prerm \
    DEBIAN/postrm

###############################################################################
# Clean Previous Build
###############################################################################

info "Cleaning previous build..."

mkdir -p Build

find Build -mindepth 1 ! -name ".gitkeep" -exec rm -rf {} +

success "Build directory ready."

###############################################################################
# Calculate Installed Size
###############################################################################

info "Calculating installed size..."

SIZE=$(du -sk usr | awk '{total += $1} END {print total}')

###############################################################################
# Prepare Package Staging
###############################################################################

info "Preparing package staging..."

STAGING="Build/.temp"

rm -rf "$STAGING"

mkdir -p "$STAGING"

cp -a DEBIAN "$STAGING/"
cp -a usr "$STAGING/"

MAN_DIR="$STAGING/usr/share/man/man1"

if [ -f "$MAN_DIR/debian-package-template.1" ]; then
    gzip -9 -n -f "$MAN_DIR/debian-package-template.1"
fi

###############################################################################
# Prepare Documentation
###############################################################################

info "Preparing documentation..."

DOC_DIR="$STAGING/usr/share/doc/${PACKAGE_NAME}"

mkdir -p "$DOC_DIR"

# cp LICENSE.md "$DOC_DIR/copyright"

if [ -f "$DOC_DIR/changelog" ]; then
    gzip -9 -n -f "$DOC_DIR/changelog"
fi

sed -i "s/^Installed-Size:.*/Installed-Size: ${SIZE}/" \
    "$STAGING/DEBIAN/control"

success "Documentation prepared."

###############################################################################
# Normalize Permissions
###############################################################################

find "$STAGING" -type d -exec chmod 755 {} \;
find "$STAGING" -type f -exec chmod 644 {} \;

chmod 755 "$STAGING/usr/bin/debian-package-template"
chmod 755 "$STAGING/usr/lib/debian-package-template/dpt"

chmod 755 "$STAGING/DEBIAN/postinst"
chmod 755 "$STAGING/DEBIAN/prerm"
chmod 755 "$STAGING/DEBIAN/postrm"

success "Package staging ready."

###############################################################################
# Build Package
###############################################################################

PACKAGE="${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"

info "Building package..."

dpkg-deb \
    --root-owner-group \
    --build \
    "$STAGING" \
    "Build/${PACKAGE}"

success "Package built successfully."

###############################################################################
# Remove Temporary Build Files
###############################################################################

info "Removing temporary build files..."

rm -rf "$STAGING"

success "Temporary files removed."

###############################################################################
# Lintian
###############################################################################

if command -v lintian >/dev/null 2>&1
then
    echo
    info "Running Lintian..."

    lintian "Build/${PACKAGE}" || true

else

    warning "Lintian not installed. Skipping validation."

fi

###############################################################################
# Finished
###############################################################################

echo
echo "=================================================="
echo " Build Complete"
echo "=================================================="

echo
echo "Package:"
echo "  Build/${PACKAGE}"

echo
echo "Install with:"
echo
echo "sudo apt install ./Build/${PACKAGE}"
echo
