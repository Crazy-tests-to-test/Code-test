#!/bin/bash
# Example script to add dependencies to the Backdoor project

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Adding Dependencies to Backdoor Project Example ===${NC}"

# Create a temporary dependencies file with real examples
cat << 'EOF' > temp-dependencies.txt
# Example dependencies to add
https://github.com/onevcat/Kingfisher.git|from:7.6.2|Kingfisher|Lightweight image downloading/caching library
https://github.com/socketio/socket.io-client-swift.git|from:16.1.0|SocketIO|Socket.IO client for iOS/macOS
EOF

echo -e "${BLUE}Created temporary dependencies file with example packages${NC}"
echo -e "${BLUE}Running add-dependencies script...${NC}"

# Check if add-dependencies.sh exists and is executable
if [[ ! -f "./add-dependencies.sh" ]]; then
    echo "Error: add-dependencies.sh not found"
    exit 1
fi

# Make it executable if it's not already
chmod +x ./add-dependencies.sh

# Run the script with verbose output and using our temp file
./add-dependencies.sh --file temp-dependencies.txt --verbose

echo -e "${GREEN}Example completed!${NC}"
echo -e "${BLUE}You can now check Package.swift to see the changes${NC}"
echo -e "${BLUE}To apply these changes to the Xcode project, run:${NC}"
echo -e "${BLUE}./regenerate-project.sh${NC}"
echo
echo -e "${BLUE}Note: This was just a demonstration. For production use:${NC}"
echo -e "1. Create your own dependencies.txt file"
echo -e "2. Run ./add-dependencies.sh [options]"
echo -e "3. Regenerate the Xcode project"

# Clean up
rm temp-dependencies.txt
