This directory intentionally has NO values file in git.

Case 14 / 15 pre-hook creates `templates/values.yaml` here at runtime. That is the
whole point: the single RenderingStep fetch runs BEFORE the pre-hook, so before
the fix nothing ever discovers the file the hook just wrote.
