import os
import re
import uuid

def generate_id():
    return uuid.uuid4().hex[:24].upper()

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    pbxproj_path = os.path.join(script_dir, 'flyflyfly.xcodeproj/project.pbxproj')
    with open(pbxproj_path, 'r') as f:
        content = f.read()

    # Find all swift files in flyflyfly
    all_swift_files = []
    for root, dirs, files in os.walk('flyflyfly'):
        for file in files:
            if file.endswith('.swift'):
                rel_path = os.path.join(root, file)
                all_swift_files.append(rel_path)

    # Get existing file references
    file_ref_matches = re.findall(r'([0-9A-F]{24}) /\* (.*?) \*/ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "(.*?)"; sourceTree = "<group>"; };', content)
    existing_file_names = {m[1] for m in file_ref_matches}
    existing_paths = {m[2] for m in file_ref_matches}
    
    # We need to map file name to its ID
    name_to_id = {m[1]: m[0] for m in file_ref_matches}

    # Find missing files
    missing_files = []
    for f in all_swift_files:
        name = os.path.basename(f)
        if name not in existing_file_names:
            missing_files.append(f)

    if not missing_files:
        print("No missing files found.")
        # But wait, user wants to ENSURE they are in the build phase too.
    else:
        print(f"Found {len(missing_files)} missing files: {missing_files}")

    # Add missing files to PBXFileReference section
    file_ref_section_start = content.find('/* Begin PBXFileReference section */')
    file_ref_section_end = content.find('/* End PBXFileReference section */')
    
    new_file_refs = []
    for f in missing_files:
        name = os.path.basename(f)
        file_id = generate_id()
        name_to_id[name] = file_id
        new_ref = f'\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};'
        new_file_refs.append(new_ref)
    
    if new_file_refs:
        insertion_point = file_ref_section_end
        content = content[:insertion_point] + '\n'.join(new_file_refs) + '\n' + content[insertion_point:]

    # Add to PBXGroup sections
    # We need to find the correct group for each file.
    for f in missing_files:
        name = os.path.basename(f)
        file_id = name_to_id[name]
        parent_dir = os.path.dirname(f)
        group_name = os.path.basename(parent_dir)
        
        # Special case for flyflyfly root
        if parent_dir == 'flyflyfly':
             group_search = r'([0-9A-F]{24}) /\* flyflyfly \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n'
        else:
             group_search = r'([0-9A-F]{24}) /\* ' + re.escape(group_name) + r' \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n'
        
        match = re.search(group_search, content)
        if match:
            insertion_point = match.end()
            content = content[:insertion_point] + f'\t\t\t\t{file_id},\n' + content[insertion_point:]
        else:
            print(f"Could not find group for {f} (group name: {group_name})")

    # Add to PBXBuildFile section
    build_file_section_start = content.find('/* Begin PBXBuildFile section */')
    build_file_section_end = content.find('/* End PBXBuildFile section */')
    
    # Check which files (existing or new) are missing from PBXBuildFile
    build_file_matches = re.findall(r'([0-9A-F]{24}) /\* (.*?) in Sources \*/ = {isa = PBXBuildFile; fileRef = ([0-9A-F]{24}) /\* (.*?) \*/; };', content)
    existing_build_file_names = {m[1] for m in build_file_matches}
    
    new_build_files = []
    new_build_file_ids = []
    for f in all_swift_files:
        name = os.path.basename(f)
        if name not in existing_build_file_names:
            file_id = name_to_id.get(name)
            if not file_id:
                print(f"Error: No file ID for {name}")
                continue
            build_id = generate_id()
            new_build_file_ids.append(build_id)
            new_build_file = f'\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};'
            new_build_files.append(new_build_file)
            print(f"Adding {name} to build files")

    if new_build_files:
        insertion_point = build_file_section_end
        content = content[:insertion_point] + '\n'.join(new_build_files) + '\n' + content[insertion_point:]

    # Add to PBXSourcesBuildPhase section for flyflyfly target
    # Target ID for flyflyfly is CA9AF84C2F5539E300AC05E8
    # We need to find the Sources build phase of this target.
    # Actually, the PBXSourcesBuildPhase section has comments like /* Sources */
    # There are multiple Sources phases (for tests, etc).
    # CA9AF84C2F5539E300AC05E8 uses CA9AF8492F5539E300AC05E8 as Sources phase.
    
    sources_phase_search = r'CA9AF8492F5539E300AC05E8 /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = \(\n'
    match = re.search(sources_phase_search, content)
    if match:
        insertion_point = match.end()
        build_file_entries = [f'\t\t\t\t{bid},\n' for bid in new_build_file_ids]
        content = content[:insertion_point] + ''.join(build_file_entries) + content[insertion_point:]
    else:
        print("Could not find Sources build phase for flyflyfly target")

    with open(pbxproj_path, 'w') as f:
        f.write(content)
    print("Successfully updated project.pbxproj")

if __name__ == '__main__':
    main()
