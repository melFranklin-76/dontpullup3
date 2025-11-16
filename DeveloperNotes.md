## Developer Notes

### Ignored Warnings and Errors

- **Missing `default.csv` warning**
  - Console message: `Failed to locate resource named "default.csv"`.
  - This file is optional for map styling; ignore this warning during development/testing unless you specifically need the asset.

- **Empty dSYM warning**
  - Console/Xcode message: `empty dSYM file detected, dSYM was created with an executable with no debug info.`
  - Safe to ignore for debug builds. Enable dSYM generation for archive/release builds if you need symbolicated crash logs.

Only the warnings listed above are considered benign. Investigate and fix any other console warnings/errors. Document additional benign warnings here once confirmed so the whole team knows they can be ignored.
