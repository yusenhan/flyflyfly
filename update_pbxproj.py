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

    # Find all relevant files in flyflyfly
    target_files = []
    for root, dirs, files in os.walk('flyflyfly'):
        for file in files:
            if file.endswith(('.swift', '.hpp', '.cpp', '.h', '.mm')):
                rel_path = os.path.join(root, file)
                target_files.append(rel_path)

    # File type mapping
    ext_to_type = {
        '.swift': 'sourcecode.swift',
        '.hpp': 'sourcecode.cpp.h',
        '.cpp': 'sourcecode.cpp.cpp',
        '.h': 'sourcecode.c.h',
        '.mm': 'sourcecode.cpp.objcpp'
    }

    # Get existing file references
    file_ref_matches = re.findall(r'([0-9A-F]{24}) /\* (.*?) \*/ = {isa = PBXFileReference; lastKnownFileType = (.*?); path = (.*?); sourceTree = "<group>"; };', content)
    existing_file_names = {m[1] for m in file_ref_matches}
    name_to_id = {m[1]: m[0] for m in file_ref_matches}

    # Find missing files
    missing_files = []
    for f in target_files:
        name = os.path.basename(f)
        if name not in existing_file_names:
            missing_files.append(f)

    if missing_files:
        print(f"Found {len(missing_files)} missing files: {missing_files}")
        file_ref_section_end = content.find('/* End PBXFileReference section */')
        new_file_refs = []
        for f in missing_files:
            name = os.path.basename(f)
            ext = os.path.splitext(f)[1]
            file_id = generate_id()
            name_to_id[name] = file_id
            file_type = ext_to_type.get(ext, 'text')
            new_ref = f'\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = "{name}"; sourceTree = "<group>"; }};'
            new_file_refs.append(new_ref)
        content = content[:file_ref_section_end] + '\n'.join(new_file_refs) + '\n' + content[file_ref_section_end:]

        # Add to PBXGroup sections
        for f in missing_files:
            name = os.path.basename(f)
            file_id = name_to_id[name]
            parent_dir = os.path.dirname(f)
            group_name = os.path.basename(parent_dir)
            
            if parent_dir == 'flyflyfly':
                 group_search = r'([0-9A-F]{24}) /\* flyflyfly \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n'
            else:
                 group_search = r'([0-9A-F]{24}) /\* ' + re.escape(group_name) + r' \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n'
            
            match = re.search(group_search, content)
            if match:
                insertion_point = match.end()
                content = content[:insertion_point] + f'\t\t\t\t{file_id},\n' + content[insertion_point:]

    # Build files
    build_file_section_end = content.find('/* End PBXBuildFile section */')
    build_file_matches = re.findall(r'([0-9A-F]{24}) /\* (.*?) in Sources \*/ = {isa = PBXBuildFile; fileRef = ([0-9A-F]{24}) /\* (.*?) \*/; };', content)
    existing_build_file_names = {m[1] for m in build_file_matches}
    
    new_build_files = []
    new_build_file_ids = []
    for f in target_files:
        if not f.endswith(('.cpp', '.mm', '.swift')): continue 
        name = os.path.basename(f)
        if name not in existing_build_file_names:
            file_id = name_to_id.get(name)
            if not file_id: continue
            build_id = generate_id()
            new_build_file_ids.append(build_id)
            new_build_file = f'\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};'
            new_build_files.append(new_build_file)

    if new_build_files:
        content = content[:build_file_section_end] + '\n'.join(new_build_files) + '\n' + content[build_file_section_end:]
        sources_phase_search = r'CA9AF8492F5539E300AC05E8 /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = \(\n'
        match = re.search(sources_phase_search, content)
        if match:
            insertion_point = match.end()
            build_file_entries = [f'\t\t\t\t{bid},\n' for bid in new_build_file_ids]
            content = content[:insertion_point] + ''.join(build_file_entries) + content[insertion_point:]

    # Build Settings
    content = re.sub(r'CLANG_CXX_LANGUAGE_STANDARD = ".*?";', 'CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";', content)
    
    # Set Bridging Header
    if 'SWIFT_OBJC_BRIDGING_HEADER' not in content:
        content = content.replace('SWIFT_VERSION = 5.9;', 'SWIFT_VERSION = 5.9;\n\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "flyflyfly/flyflyfly-Bridging-Header.h";')
    else:
        content = re.sub(r'SWIFT_OBJC_BRIDGING_HEADER = ".*?";', 'SWIFT_OBJC_BRIDGING_HEADER = "flyflyfly/flyflyfly-Bridging-Header.h";', content)

    with open(pbxproj_path, 'w') as f:
        f.write(content)
    print("Successfully updated project.pbxproj with Obj-C++ Bridge support")

if __name__ == '__main__':
    main()
