#!/bin/bash
# Test script for the dependency manager
# This script verifies that the dependency manager works correctly

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${BLUE}=== Testing Dependency Manager Script ===${NC}"

# Check if add-dependencies.sh exists
if [[ ! -f "./add-dependencies.sh" ]]; then
    echo -e "${RED}Error: add-dependencies.sh not found${NC}"
    exit 1
fi

# Make add-dependencies.sh executable
chmod +x ./add-dependencies.sh

# Create a backup of the original Package.swift
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="Package.swift.test-backup.${TIMESTAMP}"
cp Package.swift "$BACKUP_FILE"
echo -e "${BLUE}Created backup of Package.swift at $BACKUP_FILE${NC}"

# Create a test dependencies file
TEST_DEPS_FILE="test-dependencies.${TIMESTAMP}.txt"
cat << 'EOF' > "$TEST_DEPS_FILE"
# Test dependencies
https://github.com/test/example1|from:1.0.0|ExampleOne,ExampleOneUI|Test framework 1
https://github.com/test/example2|2.3.4|ExampleTwo|Test framework 2
https://github.com/test/example3|branch:develop|ExampleThree|Test framework 3
EOF
echo -e "${BLUE}Created test dependencies file at $TEST_DEPS_FILE${NC}"

# Run the dependency manager script in dry-run mode
echo -e "${BLUE}Running dependency manager script...${NC}"
OUTPUT_FILE="test-output.${TIMESTAMP}.log"
./add-dependencies.sh --file "$TEST_DEPS_FILE" --verbose > "$OUTPUT_FILE" 2>&1 || {
    echo -e "${RED}Error: Dependency manager script failed${NC}"
    echo -e "${YELLOW}Check $OUTPUT_FILE for details${NC}"
    # Restore original Package.swift
    cp "$BACKUP_FILE" Package.swift
    exit 1
}

# Verify that the dependencies were added to Package.swift
echo -e "${BLUE}Checking if dependencies were added to Package.swift...${NC}"
TESTS_PASSED=true

# Check for dependency URLs
for url in "https://github.com/test/example1" "https://github.com/test/example2" "https://github.com/test/example3"; do
    if grep -q "$url" Package.swift; then
        echo -e "${GREEN}✓ Found dependency URL: $url${NC}"
    else
        echo -e "${RED}✗ Failed to find dependency URL: $url${NC}"
        TESTS_PASSED=false
    fi
done

# Check for product dependencies
for product in "ExampleOne" "ExampleOneUI" "ExampleTwo" "ExampleThree"; do
    if grep -q "\"$product\"" Package.swift; then
        echo -e "${GREEN}✓ Found product dependency: $product${NC}"
    else
        echo -e "${RED}✗ Failed to find product dependency: $product${NC}"
        TESTS_PASSED=false
    fi
done

# Restore original Package.swift
echo -e "${BLUE}Restoring original Package.swift...${NC}"
cp "$BACKUP_FILE" Package.swift

# Clean up test files
rm -f "$TEST_DEPS_FILE" "$OUTPUT_FILE"

# Print test results
if [[ "$TESTS_PASSED" == true ]]; then
    echo -e "${GREEN}=== All tests passed! ===${NC}"
    echo -e "${GREEN}The dependency manager script is working correctly${NC}"
else
    echo -e "${RED}=== Some tests failed ===${NC}"
    echo -e "${YELLOW}Please check the script for issues${NC}"
    exit 1
fi

echo -e "${BLUE}Original Package.swift restored from $BACKUP_FILE${NC}"
echo -e "${BLUE}Test files cleaned up${NC}"
echo
echo -e "${GREEN}You can now use the dependency manager script with your actual dependencies${NC}"
echo -e "${BLUE}Create a dependencies.txt file with your dependencies${NC}"
echo -e "${BLUE}Run ./add-dependencies.sh to add them to your project${NC}"
