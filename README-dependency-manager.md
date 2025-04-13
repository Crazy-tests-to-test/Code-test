# Dependency Manager for Backdoor Xcode Project

This tool automates the process of adding Swift Package Manager dependencies to the Backdoor project. It updates both `Package.swift` and enables automatic regeneration of the Xcode project files.

## Features

- Add multiple dependencies in a single operation
- Support for different version specifications (exact version, minimum version, branch)
- Automatically add product dependencies for Shared and iOS components
- Optional automatic project regeneration
- Backup of original files before modifications

## Prerequisites

- Bash shell environment
- Xcode command-line tools installed
- Existing Package.swift file in the project root

## Installation

1. Clone this repository or download the script files
2. Make the script executable:
   ```
   chmod +x add-dependencies.sh
   ```
3. Place in your project directory or add to your PATH

## Usage

```
./add-dependencies.sh [options]
```

### Options

- `-f, --file <file>`: Specify dependency file (default: dependencies.txt)
- `-p, --package <file>`: Specify Package.swift file (default: Package.swift)
- `-r, --regenerate`: Automatically regenerate project after adding dependencies
- `-v, --verbose`: Enable verbose output
- `-h, --help`: Display help message

## Dependency File Format

The dependencies file uses a pipe-separated format with four fields:

```
url|version|products|comment
```

Where:
- `url`: The Git repository URL for the package
- `version`: Version specification (see formats below)
- `products`: Comma-separated list of products to include from the package
- `comment`: Optional comment/description (will be added as code comment)

### Version Specification Formats

- `1.2.3`: Exact version
- `from:1.2.3`: Minimum version requirement
- `branch:main`: Specific branch

## Example Dependency File

```
# Format: url|version|products|comment
https://github.com/airbnb/lottie-spm.git|from:4.5.1|Lottie|Animation framework
https://github.com/SDWebImage/SDWebImage.git|5.15.8|SDWebImage,SDWebImageMapKit|Image loading and caching
https://github.com/ReactiveX/RxSwift.git|from:6.5.0|RxSwift,RxCocoa|Reactive programming
```

## Example Usage

1. Create a file named `dependencies.txt` with your dependencies
2. Run the script:
   ```
   ./add-dependencies.sh
   ```
3. If you want to automatically regenerate the project:
   ```
   ./add-dependencies.sh --regenerate
   ```

## Integration with Build Process

You can integrate this script with your CI/CD pipeline by:

1. Running it as part of your build process
2. Adding it as a pre-commit hook
3. Combining it with the existing `regenerate-project.sh` script

## How It Works

The script performs the following actions:

1. Parses the dependencies file
2. Creates a backup of your Package.swift
3. Updates the dependencies section in Package.swift
4. Updates the target dependencies section with product dependencies
5. Optionally triggers project regeneration using regenerate-project.sh

## Troubleshooting

If you encounter issues:

1. Use the `--verbose` flag to see detailed logging
2. Check the backup files created before modifications
3. Ensure your dependencies file uses the correct format
4. Verify that package names and product names are correct

A backup of your original Package.swift is created before any modifications, with the timestamp in the filename.

## Limitations

- The script assumes a standard Swift Package Manager project structure
- It only updates the first target found in Package.swift
- Dependencies are added for the Shared and iOS folders only
