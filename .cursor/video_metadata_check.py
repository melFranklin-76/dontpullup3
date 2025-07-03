#!/usr/bin/env python3
import os, sys
errors = []
for root, _, files in os.walk('.'):
    for f in files:
        if f.endswith('.swift'):
            content = open(os.path.join(root, f)).read()
            if 'presentPhotoPicker' in content and 'checkVideoMetadata' not in content:
                errors.append(os.path.join(root, f))
if errors:
    print("❌ Missing metadata check in:\n" + "\n".join(errors))
    sys.exit(1)
