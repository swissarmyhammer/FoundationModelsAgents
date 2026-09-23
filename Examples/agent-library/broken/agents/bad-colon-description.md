---
name: bad-colon-description
description: Deploy to staging: run the smoke tests first, then promote.
---

The one defect of this file: the `description:` value holds an unquoted `: `.
A strict YAML parser reads it as a nested mapping, thus the first decode
fails. The decode retries one time with the value in quotes, and records a
note.
