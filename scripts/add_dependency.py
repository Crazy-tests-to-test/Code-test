#!/usr/bin/env python3
"""
Script to add Swift Package Manager dependencies to the backdoor.xcodeproj project.
This script updates both project.pbxproj and Package.resolved files.

Usage:
    python3 add_dependency.py [dependencies_file]

Where dependencies_file is a JSON file with dependencies (defaults to dep-bdg.json if not provided).
The file should have the following format:
[
    {
        "name": "Example",
        "url": "https://github.com/example/example",
        "requirement": {
            "kind": "upToNextMajorVersion",  // or "branch", "exactVersion", "revision"
            "minimumVersion": "1.0.0"  // or "branch": "main", "revision": "abcdef"
        },
        "products": ["ExampleProduct", "ExampleOtherProduct"]
    }
]
"""

import argparse
import json
import os
import re
import sys
import uuid
import subprocess
from datetime import datetime

# Path constants
PROJECT_FILE = 'backdoor.xcodeproj/project.pbxproj'
PACKAGE_RESOLVED_FILE = 'backdoor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
DEFAULT_DEPENDENCY_FILE = 'dep-bdg.json'

def generate_uuid_like_id():
    """Generate a UUID-like ID similar to those used in the project file."""
    random_id = uuid.uuid4().hex.upper()
    return random_id[:8] + random_id[8:12] + random_id[12:16]

def read_project_file():
    """Read the project.pbxproj file."""
    with open(PROJECT_FILE, 'r') as f:
        return f.read()

def read_package_resolved():
    """Read the Package.resolved file."""
    with open(PACKAGE_RESOLVED_FILE, 'r') as f:
        return json.load(f)

def write_project_file(content):
    """Write the updated project.pbxproj file."""
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

def write_package_resolved(content):
    """Write the updated Package.resolved file."""
    with open(PACKAGE_RESOLVED_FILE, 'w') as f:
        json.dump(content, f, indent=2)

def get_package_name_from_url(url):
    """Extract the package name from the repository URL."""
    # Get the last part of the URL (the repo name)
    repo_name = url.split('/')[-1]
    # Remove .git if present
    if repo_name.endswith('.git'):
        repo_name = repo_name[:-4]
    return repo_name

def add_to_project_file(project_content, dependency):
    """Add the dependency to the project.pbxproj file."""
    name = dependency['name']
    url = dependency['url']
    requirement = dependency['requirement']
    products = dependency['products']
    
    # Generate a unique ID for the package reference
    package_id = generate_uuid_like_id()
    
    # Find the end of the XCRemoteSwiftPackageReference section
    package_ref_section_end = re.search(r'\/\* End XCRemoteSwiftPackageReference section \*\/', project_content)
    if not package_ref_section_end:
        raise Exception("Could not find end of XCRemoteSwiftPackageReference section")
    
    # Create the package reference entry
    package_ref_entry = f"\t\t{package_id} /* XCRemoteSwiftPackageReference \"{name}\" */ = {{\n"
    package_ref_entry += f"\t\t\tisa = XCRemoteSwiftPackageReference;\n"
    package_ref_entry += f"\t\t\trepositoryURL = \"{url}\";\n"
    package_ref_entry += f"\t\t\trequirement = {{\n"
    
    if requirement['kind'] == 'upToNextMajorVersion':
        package_ref_entry += f"\t\t\t\tkind = upToNextMajorVersion;\n"
        package_ref_entry += f"\t\t\t\tminimumVersion = {requirement['minimumVersion']};\n"
    elif requirement['kind'] == 'branch':
        package_ref_entry += f"\t\t\t\tbranch = {requirement['branch']};\n"
        package_ref_entry += f"\t\t\t\tkind = branch;\n"
    elif requirement['kind'] == 'exactVersion':
        package_ref_entry += f"\t\t\t\tkind = exactVersion;\n"
        package_ref_entry += f"\t\t\t\tversion = {requirement['version']};\n"
    elif requirement['kind'] == 'revision':
        package_ref_entry += f"\t\t\t\tkind = revision;\n"
        package_ref_entry += f"\t\t\t\trevision = {requirement['revision']};\n"
    
    package_ref_entry += "\t\t\t};\n"
    package_ref_entry += "\t\t};\n"
    
    # Insert the package reference entry
    insert_position = package_ref_section_end.start()
    project_content = project_content[:insert_position] + package_ref_entry + project_content[insert_position:]
    
    # Find the end of the packageReferences section in the PBXProject
    package_refs_in_project = re.search(r'packageReferences = \(\s*([^;]*)\s*\);', project_content)
    if not package_refs_in_project:
        raise Exception("Could not find packageReferences section in PBXProject")
    
    # Add the reference to the packageReferences list
    refs_list = package_refs_in_project.group(1)
    if refs_list.strip():
        # If there are already refs, add a comma
        new_refs_list = refs_list.rstrip() + f",\n\t\t\t\t{package_id} /* XCRemoteSwiftPackageReference \"{name}\" */\n\t\t\t"
    else:
        # If no refs yet, just add the new one
        new_refs_list = f"\n\t\t\t\t{package_id} /* XCRemoteSwiftPackageReference \"{name}\" */\n\t\t\t"
    
    project_content = project_content.replace(
        f"packageReferences = (\n\t\t\t\t{refs_list}\n\t\t\t);",
        f"packageReferences = (\n\t\t\t\t{new_refs_list}\n\t\t\t);"
    )
    
    # Find the end of the XCSwiftPackageProductDependency section
    product_dependency_section_end = re.search(r'\/\* End XCSwiftPackageProductDependency section \*\/', project_content)
    if not product_dependency_section_end:
        raise Exception("Could not find end of XCSwiftPackageProductDependency section")
    
    # Create product dependency entries for each product
    product_dependencies = ""
    product_ids = []
    
    for product in products:
        product_id = generate_uuid_like_id()
        product_ids.append((product_id, product))
        
        product_entry = f"\t\t{product_id} /* {product} */ = {{\n"
        product_entry += f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
        product_entry += f"\t\t\tpackage = {package_id} /* XCRemoteSwiftPackageReference \"{name}\" */;\n"
        product_entry += f"\t\t\tproductName = {product};\n"
        product_entry += "\t\t};\n"
        
        product_dependencies += product_entry
    
    # Insert the product dependencies
    insert_position = product_dependency_section_end.start()
    project_content = project_content[:insert_position] + product_dependencies + project_content[insert_position:]
    
    # Find the PBXFrameworksBuildPhase section using a more robust approach
    # First, find the begin marker for the PBXFrameworksBuildPhase section
    frameworks_begin = re.search(r'\/\* Begin PBXFrameworksBuildPhase section \*\/', project_content)
    frameworks_end = re.search(r'\/\* End PBXFrameworksBuildPhase section \*\/', project_content)
    
    if not frameworks_begin or not frameworks_end:
        print("Project structure diagnostic information:")
        print(f"Found Begin PBXFrameworksBuildPhase: {frameworks_begin is not None}")
        print(f"Found End PBXFrameworksBuildPhase: {frameworks_end is not None}")
        # Look for similar sections to help with debugging
        other_sections = re.findall(r'\/\* Begin ([A-Za-z]+) section \*\/', project_content)
        print(f"Found these sections: {', '.join(other_sections)}")
        raise Exception("Could not find PBXFrameworksBuildPhase section markers")
    
    # Extract the frameworks section content
    frameworks_section_content = project_content[frameworks_begin.end():frameworks_end.start()]
    
    # Find the build phase for the main target
    # This is more flexible than the previous approach
    build_phase_match = re.search(r'([A-F0-9]+)\s+\/\*\s*Frameworks\s*\*\/\s+=\s+\{\s*isa\s+=\s+PBXFrameworksBuildPhase;[^{]*files\s+=\s+\(\s*(.*?)\s*\);', 
                                 frameworks_section_content, re.DOTALL)
    
    if not build_phase_match:
        # Alternative pattern, try a more general match
        build_phase_match = re.search(r'([A-F0-9]+).*?isa\s+=\s+PBXFrameworksBuildPhase;.*?files\s+=\s+\(\s*(.*?)\s*\);', 
                                     frameworks_section_content, re.DOTALL)
    
    if not build_phase_match:
        print("Failed to find framework build phase. Section content:")
        print(frameworks_section_content[:500] + "..." if len(frameworks_section_content) > 500 else frameworks_section_content)
        raise Exception("Could not find PBXFrameworksBuildPhase files section")
    
    build_phase_id = build_phase_match.group(1)
    frameworks_list = build_phase_match.group(2)
    
    # Add the products to the frameworks build phase
    frameworks_entries = ""
    
    for product_id, product in product_ids:
        entry_id = generate_uuid_like_id()
        frameworks_entries += f"\n\t\t\t\t{entry_id} /* {product} in Frameworks */,"
    
    if frameworks_list.strip():
        # If there are already frameworks, add after the last one
        new_frameworks_list = frameworks_list.rstrip() + frameworks_entries
    else:
        # If no frameworks yet, just add the new ones
        new_frameworks_list = frameworks_entries.lstrip()
    
    # Replace the old files list with the new one
    # This is more robust as it matches the exact pattern we found
    old_files_section = f"files = (\n\t\t\t\t{frameworks_list}\n\t\t\t);"
    new_files_section = f"files = (\n\t\t\t\t{new_frameworks_list}\n\t\t\t);"
    
    project_content = project_content.replace(old_files_section, new_files_section)
    
    # If the exact replacement failed, try a more flexible approach
    if old_files_section not in project_content:
        # Create a more flexible pattern with a regex
        pattern = re.compile(r'(files\s+=\s+\()(\s*.*?\s*)(\);)', re.DOTALL)
        # Replace within the PBXFrameworksBuildPhase section
        section_start = project_content.find("/* Begin PBXFrameworksBuildPhase section */")
        section_end = project_content.find("/* End PBXFrameworksBuildPhase section */", section_start)
        
        if section_start != -1 and section_end != -1:
            section = project_content[section_start:section_end]
            updated_section = pattern.sub(lambda m: f"{m.group(1)}\n\t\t\t\t{new_frameworks_list}\n\t\t\t{m.group(3)}", section)
            project_content = project_content[:section_start] + updated_section + project_content[section_end:]
        else:
            raise Exception("Could not find PBXFrameworksBuildPhase section boundaries for flexible replacement")
    
    # Add PBXBuildFile entries for the products
    build_file_section_end = re.search(r'\/\* End PBXBuildFile section \*\/', project_content)
    if not build_file_section_end:
        raise Exception("Could not find end of PBXBuildFile section")
    
    build_file_entries = ""
    
    for product_id, product in product_ids:
        entry_id = generate_uuid_like_id()
        build_file_entry = f"\t\t{entry_id} /* {product} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {product_id} /* {product} */; }};\n"
        build_file_entries += build_file_entry
    
    # Insert the build file entries
    insert_position = build_file_section_end.start()
    project_content = project_content[:insert_position] + build_file_entries + project_content[insert_position:]
    
    return project_content

def add_to_package_resolved(package_data, dependency):
    """Add the dependency to the Package.resolved file."""
    name = dependency['name']
    url = dependency['url']
    requirement = dependency['requirement']
    
    # Check if the package is already in the file
    for pin in package_data['pins']:
        if pin['identity'].lower() == name.lower() or pin['location'].lower() == url.lower():
            print(f"Package {name} is already in Package.resolved, updating it")
            # Update the existing entry
            pin['location'] = url
            pin['identity'] = name
            return package_data
    
    # Create a new entry
    new_pin = {
        "identity": name,
        "kind": "remoteSourceControl",
        "location": url,
        "state": {}
    }
    
    # Set the state based on the requirement kind
    if requirement['kind'] == 'upToNextMajorVersion' or requirement['kind'] == 'exactVersion':
        # For version-based requirements, we would need to get the revision hash from the repository
        # For simplicity, we'll use a placeholder that XCode will fix on the next package resolution
        new_pin['state'] = {
            "revision": "placeholder-revision-hash",
            "version": requirement.get('minimumVersion', requirement.get('version', '1.0.0'))
        }
    elif requirement['kind'] == 'branch':
        new_pin['state'] = {
            "branch": requirement['branch'],
            "revision": "placeholder-revision-hash"
        }
    elif requirement['kind'] == 'revision':
        new_pin['state'] = {
            "revision": requirement['revision']
        }
    
    # Add the new pin to the list
    package_data['pins'].append(new_pin)
    
    return package_data

def fetch_revision_hash(url, version_or_branch):
    """
    Fetch the revision hash for a given version or branch.
    This is a placeholder. In a real implementation, you would use git to get the actual hash.
    """
    try:
        if version_or_branch.startswith('v'):
            # If it's a version tag starting with 'v', try without it too
            version = version_or_branch[1:]
        else:
            version = version_or_branch
        
        cmd = ['git', 'ls-remote', url, f'refs/tags/{version}', f'refs/tags/v{version}', f'refs/heads/{version_or_branch}']
        result = subprocess.run(cmd, capture_output=True, text=True)
        output = result.stdout.strip()
        
        if output:
            # Extract the hash from the first line
            hash_match = re.search(r'^([a-f0-9]+)', output.split('\n')[0])
            if hash_match:
                return hash_match.group(1)
        
        # Fallback - return a placeholder
        return "placeholder-will-be-updated-by-xcode"
    except Exception as e:
        print(f"Error fetching revision hash: {e}")
        return "placeholder-will-be-updated-by-xcode"

def backup_files():
    """Create backups of the original files."""
    timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
    os.makedirs('backups', exist_ok=True)
    
    # Create .gitignore if it doesn't exist to ensure backups aren't tracked
    gitignore_path = os.path.join('backups', '.gitignore')
    if not os.path.exists(gitignore_path):
        with open(gitignore_path, 'w') as f:
            f.write("*\n")
    
    subprocess.run(['cp', PROJECT_FILE, f'backups/project.pbxproj.{timestamp}'])
    subprocess.run(['cp', PACKAGE_RESOLVED_FILE, f'backups/Package.resolved.{timestamp}'])
    
    print(f"Created backups in 'backups' directory with timestamp {timestamp}")

def main():
    parser = argparse.ArgumentParser(description='Add Swift Package Manager dependencies to Xcode project')
    parser.add_argument('dependency_file', nargs='?', default=DEFAULT_DEPENDENCY_FILE,
                       help=f'JSON file containing dependencies to add (defaults to {DEFAULT_DEPENDENCY_FILE})')
    parser.add_argument('--debug', action='store_true', 
                       help='Enable debug mode with more detailed output')
    args = parser.parse_args()
    
    try:
        # Print which file we're using
        print(f"Using dependency file: {args.dependency_file}")
        
        # Check if file exists
        if not os.path.exists(args.dependency_file):
            print(f"Error: Dependency file '{args.dependency_file}' not found.")
            return
        
        # Load dependencies from the JSON file
        with open(args.dependency_file, 'r') as f:
            dependencies = json.load(f)
        
        # Validate the dependencies
        for dep in dependencies:
            if not all(key in dep for key in ['name', 'url', 'requirement', 'products']):
                print(f"Error: Dependency missing required keys: {dep}")
                return
        
        # Backup the original files
        backup_files()
        
        # Read the current project file and package resolved
        project_content = read_project_file()
        
        # Debug: Print project file structure if debug mode is enabled
        if args.debug:
            print("\n--- Project Structure Analysis ---")
            sections = re.findall(r'\/\* Begin ([A-Za-z]+) section \*\/', project_content)
            print(f"Detected sections: {', '.join(sections)}")
            
            # Look for PBXFrameworksBuildPhase specifically
            framework_section = re.search(r'\/\* Begin PBXFrameworksBuildPhase section \*\/(.*?)\/\* End PBXFrameworksBuildPhase section \*\/', 
                                          project_content, re.DOTALL)
            if framework_section:
                print("\nPBXFrameworksBuildPhase section found:")
                print(framework_section.group(1)[:300] + "..." if len(framework_section.group(1)) > 300 else framework_section.group(1))
            else:
                print("\nPBXFrameworksBuildPhase section NOT found!")
        
        package_data = read_package_resolved()
        
        # Process each dependency
        for dependency in dependencies:
            print(f"Adding dependency: {dependency['name']}")
            # Update the project file
            try:
                project_content = add_to_project_file(project_content, dependency)
            except Exception as e:
                print(f"Error adding {dependency['name']} to project file: {str(e)}")
                if args.debug:
                    import traceback
                    traceback.print_exc()
                raise
            
            # Update the package resolved
            try:
                package_data = add_to_package_resolved(package_data, dependency)
            except Exception as e:
                print(f"Error adding {dependency['name']} to Package.resolved: {str(e)}")
                if args.debug:
                    import traceback
                    traceback.print_exc()
                raise
        
        # Write the updated files
        write_project_file(project_content)
        write_package_resolved(package_data)
        
        print("Successfully added dependencies to the project")
        print("Note: The Package.resolved file may contain placeholder revision hashes that Xcode will update on the next build")
        
    except Exception as e:
        print(f"Error adding dependencies: {e}")
        import traceback
        traceback.print_exc()
        
        # Print additional diagnostic info in case of error
        print("\n--- Diagnostic Information ---")
        print(f"Python version: {sys.version}")
        print(f"Operating system: {os.name} - {sys.platform}")
        print(f"Working directory: {os.getcwd()}")
        print(f"File exists - project.pbxproj: {os.path.exists(PROJECT_FILE)}")
        print(f"File exists - Package.resolved: {os.path.exists(PACKAGE_RESOLVED_FILE)}")
        print(f"File exists - {args.dependency_file}: {os.path.exists(args.dependency_file)}")
        
        sys.exit(1)  # Exit with error code

if __name__ == '__main__':
    main()
