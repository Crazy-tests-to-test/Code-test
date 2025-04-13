#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Default values
DEPENDENCY_FILE="dependencies.txt"
PACKAGE_SWIFT="Package.swift"
AUTO_REGENERATE=false
VERBOSE=false

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -f, --file <file>       Specify dependency file (default: dependencies.txt)"
    echo "  -p, --package <file>    Specify Package.swift file (default: Package.swift)"
    echo "  -r, --regenerate        Automatically regenerate project after adding dependencies"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -h, --help              Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            DEPENDENCY_FILE="$2"
            shift 2
            ;;
        -p|--package)
            PACKAGE_SWIFT="$2"
            shift 2
            ;;
        -r|--regenerate)
            AUTO_REGENERATE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Check if dependency file exists
if [[ ! -f "$DEPENDENCY_FILE" ]]; then
    echo -e "${RED}Error: Dependency file '$DEPENDENCY_FILE' not found${NC}"
    exit 1
fi

# Check if Package.swift exists
if [[ ! -f "$PACKAGE_SWIFT" ]]; then
    echo -e "${RED}Error: Package.swift file '$PACKAGE_SWIFT' not found${NC}"
    exit 1
fi

# Create backup of Package.swift
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${PACKAGE_SWIFT}.backup.${TIMESTAMP}"
cp "$PACKAGE_SWIFT" "$BACKUP_FILE"
echo -e "${BLUE}Created backup of $PACKAGE_SWIFT at $BACKUP_FILE${NC}"

# Function to log verbose messages
log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG] $1${NC}"
    fi
}

# Parse dependencies
echo -e "${BLUE}Parsing dependencies from $DEPENDENCY_FILE...${NC}"

# Arrays to store the extracted data
DEPENDENCY_URLS=()
DEPENDENCY_VERSIONS=()
DEPENDENCY_PRODUCTS=()
DEPENDENCY_COMMENTS=()

# Counter for dependencies
COUNT=0

# Read the dependency file line by line
while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^# || -z "$line" ]]; then
        continue
    fi
    
    # Parse the line using | as delimiter
    IFS='|' read -r url version products comment <<< "$line"
    
    # Trim whitespace
    url=$(echo "$url" | xargs)
    version=$(echo "$version" | xargs)
    products=$(echo "$products" | xargs)
    comment=$(echo "$comment" | xargs)
    
    # Validate URL
    if [[ -z "$url" ]]; then
        echo -e "${YELLOW}Warning: Skipping line with empty URL: $line${NC}"
        continue
    fi
    
    # Store the data
    DEPENDENCY_URLS+=("$url")
    DEPENDENCY_VERSIONS+=("$version")
    DEPENDENCY_PRODUCTS+=("$products")
    DEPENDENCY_COMMENTS+=("$comment")
    
    # Increment counter
    ((COUNT++))
    
    log_verbose "Parsed dependency: URL=$url, Version=$version, Products=$products, Comment=$comment"
done < "$DEPENDENCY_FILE"

echo -e "${GREEN}Found $COUNT dependencies to add${NC}"

if [[ $COUNT -eq 0 ]]; then
    echo -e "${YELLOW}No dependencies to add. Exiting.${NC}"
    exit 0
fi

# Function to extract package name from URL
get_package_name() {
    local url="$1"
    local name=$(basename "$url" .git)
    echo "$name"
}

# Update Package.swift
echo -e "${BLUE}Updating $PACKAGE_SWIFT...${NC}"

# Read Package.swift into memory
PACKAGE_CONTENT=$(<"$PACKAGE_SWIFT")

# Identify the dependencies section
DEPS_SECTION_START=$(echo "$PACKAGE_CONTENT" | grep -n "dependencies: \[" | cut -d: -f1)
if [[ -z "$DEPS_SECTION_START" ]]; then
    echo -e "${RED}Error: Could not locate dependencies section in $PACKAGE_SWIFT${NC}"
    exit 1
fi

log_verbose "Dependencies section starts at line $DEPS_SECTION_START"

# Find the end of the dependencies section
DEPS_SECTION_END=$(echo "$PACKAGE_CONTENT" | tail -n +$DEPS_SECTION_START | grep -n "\]," | head -n 1 | cut -d: -f1)
DEPS_SECTION_END=$((DEPS_SECTION_START + DEPS_SECTION_END - 1))

log_verbose "Dependencies section ends at line $DEPS_SECTION_END"

# Extract indent from the last dependency line
LAST_DEP_LINE=$(echo "$PACKAGE_CONTENT" | sed -n "$((DEPS_SECTION_END-1))p")
INDENT=$(echo "$LAST_DEP_LINE" | sed -E 's/^([[:space:]]*).*$/\1/')

log_verbose "Using indent: '$INDENT'"

# Prepare new dependencies to add
NEW_DEPS=""
for i in $(seq 0 $((COUNT-1))); do
    url="${DEPENDENCY_URLS[$i]}"
    version="${DEPENDENCY_VERSIONS[$i]}"
    comment="${DEPENDENCY_COMMENTS[$i]}"
    
    # Format version specification
    if [[ "$version" == from:* ]]; then
        # From minimum version format
        version_value=${version#from:}
        version_spec="from: \"$version_value\""
    elif [[ "$version" == branch:* ]]; then
        # Branch format
        branch_name=${version#branch:}
        version_spec="branch: \"$branch_name\""
    else
        # Exact version format
        version_spec="\"$version\""
    fi
    
    # Add the comment if provided
    comment_text=""
    if [[ -n "$comment" ]]; then
        comment_text=" // $comment"
    fi
    
    NEW_DEPS+="${INDENT}.package(url: \"$url\", $version_spec),$comment_text\n"
    
    log_verbose "Added dependency: .package(url: \"$url\", $version_spec),$comment_text"
done

# Insert new dependencies before the closing bracket
UPDATED_CONTENT=$(echo "$PACKAGE_CONTENT" | sed "${DEPS_SECTION_END}i\\
${NEW_DEPS%\\n}")

# Identify the targets section for adding product dependencies
TARGETS_SECTION_START=$(echo "$UPDATED_CONTENT" | grep -n "targets: \[" | cut -d: -f1)
if [[ -z "$TARGETS_SECTION_START" ]]; then
    echo -e "${RED}Error: Could not locate targets section in $PACKAGE_SWIFT${NC}"
    exit 1
fi

log_verbose "Targets section starts at line $TARGETS_SECTION_START"

# Find the dependencies subsection within the first target
DEPS_SUBSECTION_START=$(echo "$UPDATED_CONTENT" | tail -n +$TARGETS_SECTION_START | grep -n "dependencies: \[" | head -n 1)
DEPS_SUBSECTION_START=$(echo "$DEPS_SUBSECTION_START" | cut -d: -f1)
DEPS_SUBSECTION_START=$((TARGETS_SECTION_START + DEPS_SUBSECTION_START - 1))

log_verbose "Target dependencies subsection starts at line $DEPS_SUBSECTION_START"

# Find the end of the dependencies subsection
DEPS_SUBSECTION_END=$(echo "$UPDATED_CONTENT" | tail -n +$DEPS_SUBSECTION_START | grep -n "\]," | head -n 1 | cut -d: -f1)
DEPS_SUBSECTION_END=$((DEPS_SUBSECTION_START + DEPS_SUBSECTION_END - 1))

log_verbose "Target dependencies subsection ends at line $DEPS_SUBSECTION_END"

# Extract indent from the last product dependency line
LAST_PROD_LINE=$(echo "$UPDATED_CONTENT" | sed -n "$((DEPS_SUBSECTION_END-1))p")
PROD_INDENT=$(echo "$LAST_PROD_LINE" | sed -E 's/^([[:space:]]*).*$/\1/')

log_verbose "Using product indent: '$PROD_INDENT'"

# Prepare new product dependencies to add
NEW_PRODS=""
for i in $(seq 0 $((COUNT-1))); do
    url="${DEPENDENCY_URLS[$i]}"
    products="${DEPENDENCY_PRODUCTS[$i]}"
    comment="${DEPENDENCY_COMMENTS[$i]}"
    
    # Get package name
    package_name=$(get_package_name "$url")
    
    # Add each product
    IFS=',' read -ra PROD_ARRAY <<< "$products"
    for product in "${PROD_ARRAY[@]}"; do
        product=$(echo "$product" | xargs)  # Trim whitespace
        
        # Add comment if this is the first product and a comment exists
        product_comment=""
        if [[ -n "$comment" && "$product" == "${PROD_ARRAY[0]}" ]]; then
            product_comment=" // $comment"
        fi
        
        NEW_PRODS+="${PROD_INDENT}.product(name: \"$product\", package: \"$package_name\"),$product_comment\n"
        
        log_verbose "Added product dependency: .product(name: \"$product\", package: \"$package_name\"),$product_comment"
    done
done

# Insert new product dependencies before the closing bracket
FINAL_CONTENT=$(echo "$UPDATED_CONTENT" | sed "${DEPS_SUBSECTION_END}i\\
${NEW_PRODS%\\n}")

# Write the updated content back to Package.swift
echo "$FINAL_CONTENT" > "$PACKAGE_SWIFT"

echo -e "${GREEN}Successfully added $COUNT dependencies to $PACKAGE_SWIFT${NC}"

# Regenerate project if requested
if [[ "$AUTO_REGENERATE" == true ]]; then
    echo -e "${BLUE}Regenerating project...${NC}"
    if [[ -f "./regenerate-project.sh" ]]; then
        chmod +x ./regenerate-project.sh
        ./regenerate-project.sh
        echo -e "${GREEN}Project regenerated successfully${NC}"
    else
        echo -e "${RED}Error: regenerate-project.sh not found${NC}"
        echo -e "${YELLOW}Please manually regenerate the project with: swift package generate-xcodeproj${NC}"
    fi
else
    echo -e "${YELLOW}To complete the process, regenerate the project by running:${NC}"
    echo -e "${BLUE}./regenerate-project.sh${NC}"
fi

echo -e "${GREEN}All done!${NC}"
