#!/bin/bash
# Set the hostname to master
hostnamectl set-hostname master

# Install git (using -y for non-interactive mode so the script doesn't hang)
dnf install git -y
sleep 10
# Navigate to /tmp and clone the repository
cd /tmp
git clone https://github.com/lerndevops/labs
sleep 5
# Execute the setup script
bash /tmp/labs/scripts/setupUser.sh
