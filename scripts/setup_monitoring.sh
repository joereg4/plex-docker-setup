#!/bin/bash

# Source common functions
source "$(dirname "$0")/common.sh"

echo "=== Monitoring Setup ==="

# Verify we're in the correct directory
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}Error: Must be run from plex-docker-setup directory${NC}"
    exit 1
fi

# Verify .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}Error: .env file not found. Run setup_plex.sh first${NC}"
    exit 1
fi

# Function to configure email
setup_email() {
    echo -e "\n${YELLOW}Setting up Email Notifications${NC}"
    
    # Install required packages
    apt-get update
    apt-get install -y mailutils postfix
    
    # Configure Postfix
    postconf -e "relayhost = [smtp.gmail.com]:587"
    postconf -e "smtp_sasl_auth_enable = yes"
    postconf -e "smtp_sasl_security_options = noanonymous"
    postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
    postconf -e "smtp_use_tls = yes"
    postconf -e "smtp_tls_security_level = encrypt"
    postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
    
    # Get Gmail credentials
    echo "Enter your Gmail app password (create at https://myaccount.google.com/apppasswords):"
    read -r email_pass
    echo "Enter Gmail address:"
    read -r smtp_user
    echo "Enter notification email address:"
    read -r notify_email
    
    # Update .env
    sed -i "s/SMTP_USER=.*/SMTP_USER=$smtp_user/" .env
    sed -i "s/SMTP_PASS=.*/SMTP_PASS=$email_pass/" .env
    sed -i "s/NOTIFY_EMAIL=.*/NOTIFY_EMAIL=$notify_email/" .env
    
    # Export for immediate use
    export SMTP_USER="$smtp_user"
    export SMTP_PASS="$email_pass"
    export NOTIFY_EMAIL="$notify_email"
    
    # Configure Postfix
    echo "[smtp.gmail.com]:587 $smtp_user:$email_pass" > /etc/postfix/sasl_passwd
    chmod 600 /etc/postfix/sasl_passwd
    postmap /etc/postfix/sasl_passwd
    
    # Restart Postfix
    service postfix restart
    
    # Send test email
    echo "Test email from Plex server at $(date)" | mail -s "Plex Email Test" "$notify_email"
    echo -e "${GREEN}✓ Test email sent to $notify_email${NC}"
}

# Function to install and configure Vultr CLI
setup_vultr() {
    echo -e "\n${YELLOW}Setting up Vultr CLI${NC}"
    
    # Install Go if needed
    if ! command -v go &> /dev/null; then
        wget https://go.dev/dl/go1.20.14.linux-amd64.tar.gz
        rm -rf /usr/local/go && tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        rm go1.20.14.linux-amd64.tar.gz
    fi
    
    # Setup Go workspace
    mkdir -p ~/go/{bin,pkg,src}
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOPATH/bin
    export GO111MODULE=on
    
    # Install Vultr CLI
    go install github.com/vultr/vultr-cli/v3@v3.3.0
    
    # Get Vultr configuration
    echo "Enter your Vultr API key (from https://my.vultr.com/settings/#settingsapi):"
    read -r api_key
    
    # Show instances and get ID
    vultr-cli instance list
    echo "Enter your Instance ID from above:"
    read -r instance_id
    
    # Show block storage and get ID
    vultr-cli block-storage list
    echo "Enter your Block Storage ID from above:"
    read -r block_id
    
    # Update .env
    sed -i "s/VULTR_API_KEY=.*/VULTR_API_KEY=$api_key/" .env
    sed -i "s/VULTR_INSTANCE_ID=.*/VULTR_INSTANCE_ID=$instance_id/" .env
    sed -i "s/VULTR_BLOCK_ID=.*/VULTR_BLOCK_ID=$block_id/" .env
    
    # Export for immediate use
    export VULTR_API_KEY="$api_key"
    export VULTR_INSTANCE_ID="$instance_id"
    export VULTR_BLOCK_ID="$block_id"
}

# Function to setup monitoring cron jobs
setup_monitoring() {
    echo -e "\n${YELLOW}Setting up monitoring jobs${NC}"
    
    # Add storage monitoring (every 5 minutes)
    (crontab -l 2>/dev/null; echo "*/5 * * * * $(pwd)/scripts/manage_storage.sh check") | crontab -
    
    echo -e "${GREEN}✓ Monitoring jobs configured${NC}"
    echo "Storage check: Every 5 minutes"
}

# Main setup
echo -e "\n${YELLOW}This will set up email notifications and Vultr storage monitoring${NC}"
setup_email
setup_vultr
setup_monitoring

# Verify configuration
echo -e "\n${GREEN}=== Configuration Complete ===${NC}"
echo -e "\n${YELLOW}Email Configuration:${NC}"
echo "SMTP_USER=$SMTP_USER"
echo "NOTIFY_EMAIL=$NOTIFY_EMAIL"
echo "SMTP_PASS=$SMTP_PASS"

echo -e "\n${YELLOW}Vultr Configuration:${NC}"
echo "VULTR_API_KEY=$VULTR_API_KEY"
echo "VULTR_INSTANCE_ID=$VULTR_INSTANCE_ID"
echo "VULTR_BLOCK_ID=$VULTR_BLOCK_ID"

echo -e "\n${YELLOW}Cron Jobs:${NC}"
crontab -l 