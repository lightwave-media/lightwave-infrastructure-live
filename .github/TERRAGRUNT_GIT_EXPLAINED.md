# How Terragrunt Clones Git Repositories

## The Terragrunt Source Directive

When you write this in a `terragrunt.hcl` file:

```hcl
terraform {
  source = "git::git@github.com:lightwave-media/lightwave-infrastructure-catalog.git//modules/budget?ref=main"
}
```

**What Terragrunt does** (step-by-step):

### Step 1: Parse the Source URL

Terragrunt recognizes the `git::` prefix and breaks down the URL:

```
git::git@github.com:lightwave-media/lightwave-infrastructure-catalog.git//modules/budget?ref=main
│    │                                                             │              │
│    └─ Git remote URL (SSH format)                               │              └─ Git ref (branch/tag)
│                                                                  └─ Path inside repo (double slash)
└─ Protocol (tells Terragrunt to use git)
```

**Parts explained**:
- `git::` - Protocol, tells Terragrunt "clone this with git"
- `git@github.com:org/repo.git` - SSH-style git remote URL
- `//modules/budget` - Path INSIDE the repo (double slash is important!)
- `?ref=main` - Which branch/tag to checkout

### Step 2: Clone the Repository

Terragrunt runs something like this **behind the scenes**:

```bash
# Terragrunt creates a temp directory
TEMP_DIR=$(mktemp -d)

# Runs git clone
git clone git@github.com:lightwave-media/lightwave-infrastructure-catalog.git $TEMP_DIR

# Checkout the specified ref
cd $TEMP_DIR
git checkout main

# Copy the specific path to working directory
cp -r $TEMP_DIR/modules/budget/* /path/to/your/terragrunt/working/dir/
```

**This is where authentication happens!** ⬆️

When git tries to clone `git@github.com:...`, it looks for:
1. **SSH key in `~/.ssh/id_rsa`** (or other configured keys)
2. **SSH agent** with loaded keys
3. **Git credential helper** if URL is HTTPS

### Step 3: Cache the Clone

Terragrunt is smart - it **caches cloned repos** in:

```
~/.terragrunt-cache/
└── {hash-of-source-url}/
    └── {module-path}/
```

**On your local machine**:
```bash
$ ls ~/.terragrunt-cache/
KJh3j4k5h6j7k8l9m0n1o2p3q4r5s6t7u8v9w0x1y2z3/  # Hash of the source URL
```

**Inside that hash directory**:
```
modules/budget/         # The actual OpenTofu/Terraform code
.terraform/             # OpenTofu working directory
.terragrunt-source-version  # Tracks which git ref was used
```

**Why caching matters**:
- First run: Clones the repo (slow)
- Subsequent runs: Uses cached copy (fast)
- Cache invalidated if `ref` changes or source URL changes

## The Authentication Problem

### What Happens in GitHub Actions

**GitHub Actions runner environment**:
```
~/.ssh/
└── (empty - no SSH keys by default)

~/.gitconfig
└── (minimal config, no credentials)
```

**When Terragrunt tries to clone**:
```bash
git clone git@github.com:lightwave-media/lightwave-infrastructure-catalog.git
# ❌ ERROR: Permission denied (publickey)
# Git tries SSH, no key found, fails
```

### The Two Solutions

#### Solution 1: Add SSH Key (The Quick Way)
```yaml
# In GitHub Actions workflow
- uses: webfactory/ssh-agent@v0.9.0
  with:
    ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}
```

**Then git clone works because**:
```bash
~/.ssh/
└── id_rsa  # ← SSH agent added the key here
```

**Why we're NOT doing this**:
- ❌ SSH keys are harder to rotate
- ❌ SSH keys don't have scoped permissions
- ❌ SSH doesn't work well with some corporate firewalls
- ❌ No audit trail (who used the key when?)

#### Solution 2: Use HTTPS + Token (The Platform Way)
```yaml
# In GitHub Actions workflow
- name: Configure Git for Terragrunt
  run: |
    git config --global url."https://oauth2:${{ secrets.GITHUB_TOKEN }}@github.com/".insteadOf "https://github.com/"
```

**Change Terragrunt source to**:
```hcl
terraform {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/budget?ref=main"
}
```

**Now git clone works because**:
```bash
git clone https://github.com/lightwave-media/lightwave-infrastructure-catalog.git

# Git sees "https://github.com" and applies the config:
# Instead of: https://github.com/...
# Uses:       https://oauth2:{TOKEN}@github.com/...

# ✅ SUCCESS: GitHub accepts the token
```

## How Git Credential Helpers Work

When you run:
```bash
git config --global url."https://oauth2:TOKEN@github.com/".insteadOf "https://github.com/"
```

**Git stores this in** `~/.gitconfig`:
```ini
[url "https://oauth2:ghp_xxxxxxxxxxxx@github.com/"]
    insteadOf = https://github.com/
```

**What happens next**:
1. Terragrunt says: "Clone `https://github.com/org/repo.git`"
2. Git checks `~/.gitconfig`
3. Git finds the `insteadOf` rule
4. Git **rewrites the URL** to: `https://oauth2:ghp_xxxx@github.com/org/repo.git`
5. Git sends request to GitHub with token in URL
6. GitHub validates token and allows clone
7. ✅ Terragrunt gets the code

## Visual Flow Diagram

### Current Flow (SSH - BROKEN)
```
Terragrunt
   │
   └─> Reads terragrunt.hcl
       │
       └─> Sees: git::git@github.com:org/repo.git//modules/budget
           │
           └─> Runs: git clone git@github.com:org/repo.git
               │
               └─> Git looks for SSH key in ~/.ssh/
                   │
                   └─> ❌ NOT FOUND
                       │
                       └─> ERROR: Permission denied (publickey)
```

### Fixed Flow (HTTPS + Token)
```
Terragrunt
   │
   └─> Reads terragrunt.hcl
       │
       └─> Sees: git::https://github.com/org/repo.git//modules/budget
           │
           └─> Runs: git clone https://github.com/org/repo.git
               │
               └─> Git checks ~/.gitconfig
                   │
                   └─> Finds insteadOf rule
                       │
                       └─> Rewrites to: https://oauth2:TOKEN@github.com/org/repo.git
                           │
                           └─> Sends HTTPS request with token
                               │
                               └─> ✅ GitHub validates token
                                   │
                                   └─> ✅ Clone succeeds
                                       │
                                       └─> Terragrunt caches in ~/.terragrunt-cache/
                                           │
                                           └─> Terragrunt copies modules/budget to working dir
                                               │
                                               └─> OpenTofu can now run!
```

## Testing This Locally

You can see Terragrunt's git behavior:

```bash
# Enable debug mode
export TERRAGRUNT_LOG_LEVEL=debug

# Run a plan
cd non-prod/us-east-1/budget
terragrunt plan

# You'll see output like:
# [DEBUG] Downloading source from git::https://github.com/...
# [DEBUG] Cloning git repository...
# [DEBUG] Checking out ref main
# [DEBUG] Copying /tmp/terragrunt-xxx/modules/budget to .terragrunt-cache/
```

**To see the cached files**:
```bash
ls -la ~/.terragrunt-cache/

# Find the hash directory for your module
find ~/.terragrunt-cache/ -name "budget"
```

## Key Takeaways

1. **Terragrunt clones git repos** during the `terragrunt plan/apply` process
2. **Authentication happens at git clone time**, not Terragrunt time
3. **SSH vs HTTPS** is a git authentication choice, not a Terragrunt choice
4. **Git credential helpers** allow token-based auth without hardcoding tokens
5. **Terragrunt caches** cloned modules to speed up subsequent runs
6. **The double slash** `//` separates "repo URL" from "path inside repo"
7. **`?ref=main`** tells git which branch/tag/commit to checkout

## Common Questions

### Q: Why not just use local file paths?
```hcl
source = "../../../lightwave-infrastructure-catalog/modules/budget"
```

**A**: Because then you'd need to clone BOTH repos every time. Using git URLs means:
- Infrastructure-live repo can be standalone
- Catalog changes are version-controlled (via `?ref=v1.0.0`)
- Teams can work on catalog without affecting live environments

### Q: Can I use different refs for different environments?
```hcl
# non-prod/us-east-1/budget/terragrunt.hcl
source = "git::https://github.com/org/repo.git//modules/budget?ref=main"

# prod/us-east-1/budget/terragrunt.hcl
source = "git::https://github.com/org/repo.git//modules/budget?ref=v1.2.3"
```

**A**: Yes! This is the recommended pattern:
- **Non-prod**: Use `ref=main` (latest)
- **Prod**: Use `ref=v1.2.3` (pinned version)

### Q: What if the catalog repo is private?
**A**: That's our current situation! Private repos need authentication:
- **Local dev**: Your SSH key or HTTPS token (from `gh auth login`)
- **GitHub Actions**: Token from `GITHUB_TOKEN` secret (what we're setting up)

### Q: Does this work with other git providers (GitLab, Bitbucket)?
**A**: Yes! The same pattern works:
```hcl
# GitLab
source = "git::https://gitlab.com/org/repo.git//modules/budget?ref=main"

# Bitbucket
source = "git::https://bitbucket.org/org/repo.git//modules/budget?ref=main"
```

You just need the appropriate credential helper configured.

## Verification Commands

After we fix this, you can verify it works:

```bash
# Check git config
git config --global --get-regexp url

# Should show:
# url.https://oauth2:{TOKEN}@github.com/.insteadof https://github.com/

# Test git clone manually
git clone https://github.com/lightwave-media/lightwave-infrastructure-catalog.git /tmp/test

# If successful, git credential helper is working!
```

## Next Steps

Now that you understand how this works, the fix is straightforward:

1. ✅ Generate GitHub token (you're about to do)
2. ✅ Update all `source` URLs from SSH to HTTPS
3. ✅ Configure git credential helper in workflows
4. ✅ Test and verify Terragrunt can clone

Let's do it! 🚀
