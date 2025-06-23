#!/usr/bin/env python3
import os, sys
errors = []
for root, _, files in os.walk('.'):
    for f in files:
        if f.endswith('.swift'):
            path = os.path.join(root, f)
            txt = open(path).read()
            if 'presentPhotoPicker' in txt and 'checkVideoMetadata' not in txt:
                errors.append(path)
if errors:
    print("❌ Missing metadata check in:\n" + "\n".join(errors))
    sys.exit(1)
