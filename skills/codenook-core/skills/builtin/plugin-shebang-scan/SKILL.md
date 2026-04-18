# plugin-shebang-scan — Install gate G10

For every regular file with the executable bit set anywhere under
`<src>`, the first line must be one of:

```
#!/bin/sh
#!/bin/bash
#!/usr/bin/env bash
#!/usr/bin/env python3
```

(Exact match; no trailing arguments.)

## CLI

```
shebang-scan.sh --src <dir> [--json]
```

Files without `+x` are ignored — they cannot be invoked as scripts.
Symlinks are not followed (G01 already verified they don't escape).
