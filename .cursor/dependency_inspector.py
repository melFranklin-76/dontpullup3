#!/usr/bin/env python3
import json
import os
import sys
import re
import argparse

def parse_args():
    parser = argparse.ArgumentParser(description='Check Swift file dependencies')
    parser.add_argument('--config', default='dependencies.json', help='Path to dependencies.json')
    return parser.parse_args()

def main():
    args = parse_args()
    
    if not os.path.exists(args.config):
        print(f"❌ Dependency config file not found: {args.config}")
        sys.exit(1)
    
    with open(args.config, 'r') as f:
        dependencies = json.load(f)
    
    errors = []
    
    for file_path, required_imports in dependencies.items():
        if not os.path.exists(file_path):
            errors.append(f"File not found: {file_path}")
            continue
            
        with open(file_path, 'r') as f:
            content = f.read()
            
        for imp in required_imports:
            import_pattern = f"import\\s+{imp}"
            if not re.search(import_pattern, content):
                errors.append(f"❌ {file_path} is missing required import: {imp}")
    
    if errors:
        print("\n".join(errors))
        sys.exit(1)
    else:
        print("✅ All dependencies verified successfully")
        sys.exit(0)

if __name__ == "__main__":
    main() 