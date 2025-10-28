#!/bin/bash
set -e

echo "=================================================="
echo "LightWave Media - Gruntwork Toolset Installer"
echo "=================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install gruntwork-installer if not already installed
if ! command_exists gruntwork-install; then
    echo -e "${YELLOW}Installing gruntwork-installer...${NC}"
    curl -LsS https://raw.githubusercontent.com/gruntwork-io/gruntwork-installer/v0.0.38/bootstrap-gruntwork-installer.sh | bash /dev/stdin --version v0.0.38
    echo -e "${GREEN}✓ gruntwork-installer installed${NC}"
else
    echo -e "${GREEN}✓ gruntwork-installer already installed${NC}"
fi

# Install cloud-nuke
if ! command_exists cloud-nuke; then
    echo -e "${YELLOW}Installing cloud-nuke...${NC}"
    mkdir -p ~/bin
    cd ~/bin
    curl -L -o cloud-nuke https://github.com/gruntwork-io/cloud-nuke/releases/download/v0.33.0/cloud-nuke_darwin_arm64
    chmod +x cloud-nuke
    echo -e "${GREEN}✓ cloud-nuke installed to ~/bin/cloud-nuke${NC}"
else
    echo -e "${GREEN}✓ cloud-nuke already installed${NC}"
fi

# Install boilerplate
if ! command_exists boilerplate; then
    echo -e "${YELLOW}Installing boilerplate...${NC}"
    mkdir -p ~/bin
    cd ~/bin
    curl -L -o boilerplate https://github.com/gruntwork-io/boilerplate/releases/download/v0.5.12/boilerplate_darwin_arm64
    chmod +x boilerplate
    echo -e "${GREEN}✓ boilerplate installed to ~/bin/boilerplate${NC}"
else
    echo -e "${GREEN}✓ boilerplate already installed${NC}"
fi

# Install pre-commit
if ! command_exists pre-commit && ! command_exists ~/Library/Python/3.10/bin/pre-commit; then
    echo -e "${YELLOW}Installing pre-commit...${NC}"
    pip3 install --user pre-commit
    echo -e "${GREEN}✓ pre-commit installed${NC}"
else
    echo -e "${GREEN}✓ pre-commit already installed${NC}"
fi

# Check for Go
if ! command_exists go; then
    echo -e "${YELLOW}⚠️  Go is not installed${NC}"
    echo -e "${YELLOW}   Install via: brew install go OR mise install${NC}"
else
    GO_VERSION=$(go version | awk '{print $3}')
    echo -e "${GREEN}✓ Go ${GO_VERSION} installed${NC}"
fi

# Check for Terragrunt
if ! command_exists terragrunt; then
    echo -e "${YELLOW}⚠️  Terragrunt is not installed${NC}"
    echo -e "${YELLOW}   Install via: brew install terragrunt OR mise install${NC}"
else
    TG_VERSION=$(terragrunt --version | head -n1)
    echo -e "${GREEN}✓ ${TG_VERSION}${NC}"
fi

# Check for Terraform/OpenTofu
if command_exists terraform; then
    TF_VERSION=$(terraform --version | head -n1)
    echo -e "${GREEN}✓ ${TF_VERSION}${NC}"
elif command_exists tofu; then
    TOFU_VERSION=$(tofu --version | head -n1)
    echo -e "${GREEN}✓ ${TOFU_VERSION}${NC}"
else
    echo -e "${YELLOW}⚠️  Terraform/OpenTofu not installed${NC}"
    echo -e "${YELLOW}   Install via: brew install terraform OR mise install${NC}"
fi

echo ""
echo -e "${GREEN}=================================================="
echo -e "✅ Tool installation complete!"
echo -e "==================================================${NC}"
echo ""
echo "Installed tools:"
echo "  - gruntwork-installer"
echo "  - cloud-nuke (~/bin/cloud-nuke)"
echo "  - boilerplate (~/bin/boilerplate)"
echo "  - pre-commit"
echo ""
echo "Next steps:"
echo "  1. Add ~/bin to your PATH if not already added"
echo "  2. Run 'make install-hooks' to setup pre-commit hooks"
echo "  3. Run 'make test' to verify installation"
echo ""
