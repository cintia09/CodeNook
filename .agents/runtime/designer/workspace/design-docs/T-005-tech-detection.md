# Design: T-005 — Enhanced Tech Stack Detection

## G1: Additional language/framework detection

Add to agent-init Step 1a:
```bash
# Existing
ls package.json Cargo.toml requirements.txt go.mod pom.xml 2>/dev/null

# NEW — additional languages
ls Gemfile 2>/dev/null        # Ruby
ls composer.json 2>/dev/null  # PHP
ls *.csproj *.sln 2>/dev/null # .NET
ls Package.swift 2>/dev/null  # Swift
ls pubspec.yaml 2>/dev/null   # Flutter/Dart
ls mix.exs 2>/dev/null        # Elixir
ls build.gradle* 2>/dev/null  # Kotlin/Android
```

## G2: Monorepo detection

```bash
# Monorepo indicators
ls lerna.json 2>/dev/null
ls pnpm-workspace.yaml 2>/dev/null
ls nx.json 2>/dev/null
ls turbo.json 2>/dev/null
ls rush.json 2>/dev/null
```

If monorepo detected, project-agents-context should list workspace packages.

## G3: README parsing for description

```bash
# If no package.json description, extract from README
if [ -f README.md ]; then
  # Get first non-empty, non-heading line as description
  DESCRIPTION=$(grep -v '^#' README.md | grep -v '^$' | head -1 | head -c 200)
fi
```

## G4: Deployment target detection

```bash
ls vercel.json 2>/dev/null        # Vercel
ls netlify.toml 2>/dev/null       # Netlify
ls serverless.yml 2>/dev/null     # Serverless Framework
ls template.yaml 2>/dev/null      # AWS SAM
ls fly.toml 2>/dev/null           # Fly.io
ls render.yaml 2>/dev/null        # Render
ls Procfile 2>/dev/null           # Heroku
ls railway.json 2>/dev/null       # Railway
```

## File to modify
| File | Change |
|------|--------|
| `skills/agent-init/SKILL.md` | Expand Step 1a with all detection categories |
