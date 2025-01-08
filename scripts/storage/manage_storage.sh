#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
ALERT_THRESHOLD=75      # Percentage - Warning email
CRITICAL_THRESHOLD=90   # Percentage - Auto expand
BLOCK_INCREMENT=50      # GB - Smaller increments


# Debug: Show current directory and .env location
echo "Current directory: $(pwd)"

# Load environment variables
if [ ! -f ".env" ] && [ ! -f "../.env" ]; then
    echo -e "${RED}Error: .env file not found in current or parent directory${NC}"
    exit 1
fi

# Try to load .env from current or parent directory
if [ -f ".env" ]; then
    set -a
    . ".env"
    set +a
elif [ -f "../.env" ]; then
    set -a
    . "../.env"
    set +a
fi

# Verify required environment variables
if [ -z "$VULTR_API_KEY" ]; then
    echo -e "${RED}Error: VULTR_API_KEY not found in .env${NC}"
    exit 1
fi

if [ -z "$VULTR_BLOCK_ID" ]; then
    echo -e "${YELLOW}Warning: VULTR_BLOCK_ID not found in .env${NC}"
    echo -e "${YELLOW}Block storage monitoring will be disabled${NC}"
fi

# Function to get current usage percentage
get_usage() {
    local mount=$1
    df -h $mount | awk 'NR==2 {sub(/%/,"",$5); print $5}'
}

# Function to get block device size
get_block_size() {
    lsblk -b /dev/vdb | awk 'NR==2 {print $4/1024/1024/1024}'  # Convert to GB
}

# Function to check if block storage exists and is mounted
check_block_storage() {
    if [ ! -b "/dev/vdb" ]; then
        echo -e "${RED}Error: Block storage device (/dev/vdb) not found${NC}"
        echo -e "${YELLOW}Possible issues:${NC}"
        echo "1. Block storage not attached in Vultr dashboard"
        echo "2. Block storage not properly configured"
        echo -e "Run ${GREEN}setup_monitoring.sh${NC} to configure block storage"
        return 1
    fi

    if ! mountpoint -q "/mnt/blockstore"; then
        echo -e "${RED}Error: Block storage not mounted at /mnt/blockstore${NC}"
        echo -e "${YELLOW}To fix:${NC}"
        echo "1. Create mount point: mkdir -p /mnt/blockstore"
        echo "2. Mount device: mount /dev/vdb /mnt/blockstore"
        echo "3. Add to fstab for persistence"
        echo -e "Or run ${GREEN}setup_monitoring.sh${NC} to configure automatically"
        return 1
    fi

    return 0
}

# Function to expand block storage using Vultr API
expand_storage() {
    local current_size=$(get_block_size)
    local new_size=$((current_size + BLOCK_INCREMENT))
    
    echo -e "${YELLOW}Expanding block storage from ${current_size}GB to ${new_size}GB${NC}"
    
    # Call Vultr API
    curl -s -H "Authorization: Bearer ${VULTR_API_KEY}" \
         -H "Content-Type: application/json" \
         -X PATCH \
         -d "{\"size_gb\": ${new_size}}" \
         "https://api.vultr.com/v2/blocks/${VULTR_BLOCK_ID}"
    
    if [ $? -eq 0 ]; then
        echo "Waiting for resize to complete..."
        sleep 30  # Give Vultr time to process
        
        # Grow the filesystem
        echo "Growing filesystem..."
        if [ ! -b "/dev/vdb" ]; then
            echo -e "${RED}Error: Block device /dev/vdb not found${NC}"
            exit 1
        fi
        resize2fs /dev/vdb
        
        # Verify expansion
        new_actual_size=$(get_block_size)
        if [ "$new_actual_size" -ge "$new_size" ]; then
            echo -e "${GREEN}Storage expansion complete${NC}"
        else
            echo -e "${RED}Warning: New size ($new_actual_size GB) less than expected ($new_size GB)${NC}"
        fi
    else
        echo -e "${RED}Failed to expand storage via Vultr API${NC}"
        exit 1
    fi
}

# Main logic
case "$1" in
    "check")
        if check_block_storage; then
            usage=$(get_usage "/mnt/blockstore")
            echo -e "Current block storage usage: ${YELLOW}${usage}%${NC}"
            
            if [ $usage -gt $CRITICAL_THRESHOLD ]; then
                echo -e "${RED}CRITICAL: Storage usage above ${CRITICAL_THRESHOLD}%${NC}"
            elif [ $usage -gt $ALERT_THRESHOLD ]; then
                echo -e "${YELLOW}WARNING: Storage usage above ${ALERT_THRESHOLD}%${NC}"
            fi
        fi
        ;;
        
    "expand")
        if check_block_storage; then
            expand_storage
        fi
        ;;
        
    "auto")
        if check_block_storage; then
            usage=$(get_usage "/mnt/blockstore")
            
            if [ $usage -gt $CRITICAL_THRESHOLD ]; then
                echo -e "${RED}Usage critical (${usage}%), expanding storage...${NC}"
                expand_storage
                # Send email notification about expansion
                echo "Block storage was automatically expanded due to reaching ${usage}% usage." | mail -s "Storage Expanded - Plex Server" "$NOTIFY_EMAIL"
            elif [ $usage -gt $ALERT_THRESHOLD ]; then
                echo -e "${YELLOW}WARNING: Usage at ${usage}%${NC}"
                # Send warning email
                echo "Block storage usage is at ${usage}%. It will be automatically expanded if it exceeds ${CRITICAL_THRESHOLD}%." | mail -s "Storage Warning - Plex Server" "$NOTIFY_EMAIL"
            else
                echo -e "${GREEN}Storage usage normal (${usage}%)${NC}"
            fi
        fi
        ;;
        
    *)
        echo "Usage: $0 {check|expand|auto}"
        echo "  check  - Check current storage usage"
        echo "  expand - Manually expand block storage"
        echo "  auto   - Automatically expand if above threshold"
        ;;
esac 