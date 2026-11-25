# Helper for the Claude commands: GitLab / GitHub issue + change (MR / PR) status, and local checks.
# Windows PowerShell 5.1 (built in) or PowerShell 7 (macOS / Linux). Run from the repo root:
#   Windows: .claude/scripts/issue-flow.cmd <command> [n | issue URL] [options]
#   macOS / Linux: pwsh -NoProfile -File .claude/scripts/issue-flow.ps1 <command> [n | issue URL] [options]
# Options: --reviewer a,b   --project owner/name   --dry-run   --draft
# Remote:  check | issue n | progress n | start n | open-change n [--draft] | find-change n | reopen n | feedback n | set-reviewer n
# Local:   fingerprint | related-tests | base-behind | review-status n
# Setup:   init | set-token
# Token: one file per host, <home>/.config/issue-flow/token-<host>.txt, or env ISSUE_FLOW_TOKEN together with ISSUE_FLOW_HOST. Never printed.
# Dot-sourcing only defines the functions.

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$script:DryRun = $false
$script:Draft = $false
$script:ProjectArg = $null
$script:ReviewerArg = $null
$script:UrlHost = $null

function Fail([string]$Message) { throw (New-Object System.Exception $Message) }
function Esc([string]$s) { [Uri]::EscapeDataString($s) }
function ToJson($o) { ConvertTo-Json -InputObject $o -Depth 12 }
function ConfigDir { $h = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }; Join-Path (Join-Path $h '.config') 'issue-flow' }

# ---------- git ----------
# The git program itself: "& git" inside the function Git would call the function (PowerShell names ignore case).
$GitExe = (Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $GitExe) { $GitExe = 'git' }
function Git {
  $out = & $GitExe -c core.quotepath=false @args 2>$null
  if ($LASTEXITCODE -ne 0) { return '' }
  return (@($out) -join "`n")
}
function Get-GitDir { $d = (Git rev-parse --git-dir).Trim(); if ($d) { $d } else { '.git' } }

# Team settings: .claude/issue-flow.json. No secrets there.
$Config = $null
$Top = (Git rev-parse --show-toplevel).Trim()
$ConfigFile = if ($Top) { Join-Path (Join-Path $Top '.claude') 'issue-flow.json' } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'issue-flow.json' }
if (Test-Path -LiteralPath $ConfigFile) { $Config = [IO.File]::ReadAllText($ConfigFile).TrimStart([char]0xFEFF) | ConvertFrom-Json }
function Pick($Value, [string]$Default) { if ($Value) { [string]$Value } else { $Default } }
$OriginHead = ((Git symbolic-ref --short refs/remotes/origin/HEAD).Trim() -replace '^origin/', '')
if (-not $OriginHead -and -not (Git rev-parse --verify --quiet refs/remotes/origin/main) -and (Git rev-parse --verify --quiet refs/remotes/origin/master)) { $OriginHead = 'master' }
$BaseBranch = Pick $Config.baseBranch (Pick $OriginHead 'main')
$StatusPrefix = Pick $Config.labels.prefix 'Status'
$LabelInProgress = Pick $Config.labels.inProgress 'Status: In progress'
$LabelAwaitingReview = Pick $Config.labels.awaitingReview 'Status: Awaiting review'

# ---------- which server ----------
# origin: https://host/owner/name(.git), git@host:owner/name(.git), ssh://git@host[:port]/owner/name(.git)
function Get-Origin {
  $url = (Git remote get-url origin).Trim()
  if ($url -match '^https?://(?:[^@/]+@)?([^/]+)/(.+?)(?:\.git)?/?$') { return @{ Host = $Matches[1]; Path = $Matches[2] } }
  if ($url -match '^ssh://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+?)(?:\.git)?/?$') { return @{ Host = $Matches[1]; Path = $Matches[2] } }
  if ($url -match '^(?:[^@/]+@)?([^/:]+):(.+?)(?:\.git)?/?$') { return @{ Host = $Matches[1]; Path = $Matches[2] } }
  return $null
}
function Get-HostUrl {
  $u = ([string]$Config.host).TrimEnd('/')
  if (-not $u) { $o = Get-Origin; if ($o) { $u = "https://$($o.Host)" } }
  if (-not $u) { Fail 'Cannot detect the server: run inside the cloned repo, or set "host" in .claude/issue-flow.json' }
  if ($u -notmatch '^https?://') { $u = "https://$u" }
  if ($u -notmatch '^https://' -and $u -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') { Fail 'The server must use https (the token is sent to it)' }
  return $u
}
function Get-HostName { (Get-HostUrl) -replace '^https?://', '' }
function Get-Provider {
  $p = ([string]$Config.provider).ToLowerInvariant()
  if (-not $p) { $p = if ((Get-HostName) -match 'github') { 'github' } else { 'gitlab' } }
  if (@('github', 'gitlab') -notcontains $p) { Fail "Unknown provider '$p' in .claude/issue-flow.json (github or gitlab)" }
  return $p
}
function IsGitHub { (Get-Provider) -eq 'github' }
function Get-ProjectPath {
  if ($script:ProjectArg) { return $script:ProjectArg }
  $o = Get-Origin
  if ($o) { return $o.Path }
  Fail 'Cannot detect the project: run inside the cloned repo, or pass --project owner/name'
}
function Get-ApiBase {
  $u = Get-HostUrl
  if (IsGitHub) { if ((Get-HostName) -eq 'github.com') { return 'https://api.github.com' } else { return "$u/api/v3" } }
  return "$u/api/v4"
}
function Get-GraphQLUrl { if ((Get-HostName) -eq 'github.com') { 'https://api.github.com/graphql' } else { "$(Get-HostUrl)/api/graphql" } }
function Get-TokenPage {
  if (IsGitHub) { "$(Get-HostUrl)/settings/personal-access-tokens/new" }
  else { "$(Get-HostUrl)/-/user_settings/personal_access_tokens?name=Claude%20commands&scopes=api" }
}
function Get-TokenHelp {
  if (IsGitHub) { 'GitHub: fine-grained token for this repository with Contents, Issues and Pull requests = Read and write' }
  else { 'GitLab: Preferences > Access tokens, scope api' }
}

# ---------- token ----------
function Get-TokenFile { Join-Path (ConfigDir) "token-$((Get-HostName) -replace '[^A-Za-z0-9.-]', '_').txt" }
# One file per host, so a token is never sent to another server. ISSUE_FLOW_TOKEN counts only for the host in ISSUE_FLOW_HOST.
function Get-Token {
  $h = Get-HostName
  if ($env:ISSUE_FLOW_TOKEN -and $env:ISSUE_FLOW_HOST -and (($env:ISSUE_FLOW_HOST -replace '^https?://', '').TrimEnd('/') -eq $h)) { return $env:ISSUE_FLOW_TOKEN.Trim() }
  $f = Get-TokenFile
  if (Test-Path -LiteralPath $f) { return [IO.File]::ReadAllText($f).TrimStart([char]0xFEFF).Trim() }
  Fail "No token for $h. Windows: double-click .claude\setup-token.cmd (or .claude/scripts/issue-flow.cmd set-token). macOS / Linux: pwsh -NoProfile -File .claude/scripts/issue-flow.ps1 set-token. $(Get-TokenHelp)"
}

# One HTTP call; never throws. @{ Ok; Status; Text }
function Send-Http([string]$Method, [string]$Url, [string]$Token, $Body) {
  try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.UserAgent = 'claude-issue-flow'
    $req.Timeout = 60000
    $req.AllowAutoRedirect = $false   # never carry the token to a redirect target
    if (IsGitHub) { $req.Accept = 'application/vnd.github+json'; $req.Headers.Add('Authorization', "Bearer $Token") }
    else { $req.Accept = 'application/json'; $req.Headers.Add('PRIVATE-TOKEN', $Token) }
    if ($null -ne $Body) {
      $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 12 -Compress))
      $req.ContentType = 'application/json; charset=utf-8'
      $req.ContentLength = $bytes.Length
      $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()
    }
    $resp = $null
    try { $resp = $req.GetResponse() } catch {
      $ex = $_.Exception; while ($ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
      if ($ex -and $ex.Response) { $resp = $ex.Response } else { return @{ Ok = $false; Status = $(if ($ex) { "$($ex.Status)" } else { 'error' }); Text = $_.Exception.Message } }
    }
    $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
    $text = $sr.ReadToEnd(); $sr.Close()
    $code = [int]$resp.StatusCode; $resp.Close()
    return @{ Ok = ($code -ge 200 -and $code -lt 300); Status = $code; Text = $text }
  } catch { return @{ Ok = $false; Status = 'error'; Text = $_.Exception.Message } }
}
function Show-Dry([string]$Method, [string]$Path, $Body) {
  $b = if ($null -ne $Body) { ConvertTo-Json -InputObject $Body -Depth 12 -Compress } else { '' }
  [Console]::Out.WriteLine("[dry-run] $Method $Path $b")
}
function Short([string]$t) { $t.Substring(0, [Math]::Min(300, $t.Length)) }
# $AllowStatus: statuses that are not an error (the call then returns nothing).
function Api([string]$Method, [string]$Path, $Body, [int[]]$AllowStatus) {
  if ($script:DryRun -and $Method -ne 'GET') { Show-Dry $Method $Path $Body; return [pscustomobject]@{} }
  $r = Send-Http $Method "$(Get-ApiBase)$Path" (Get-Token) $Body
  if (-not $r.Ok) {
    if ($AllowStatus -and $AllowStatus -contains $r.Status) { return $null }
    Fail "$Method $Path -> $($r.Status) $(Short "$($r.Text)")"
  }
  if ($r.Text) { return ($r.Text | ConvertFrom-Json) } else { return [pscustomobject]@{} }
}
# Items of a JSON array one by one; wrap in @() when a list is needed.
function ApiList([string]$Path) { (Api 'GET' $Path) | ForEach-Object { $_ } }
function GraphQL([string]$Query, $Variables, [bool]$Write) {
  if ($script:DryRun -and $Write) { Show-Dry 'GRAPHQL' ($Query -replace '\s+', ' ') $Variables; return $null }
  $r = Send-Http 'POST' (Get-GraphQLUrl) (Get-Token) ([ordered]@{ query = $Query; variables = $Variables })
  if (-not $r.Ok) { Fail "GraphQL -> $($r.Status) $(Short "$($r.Text)")" }
  $j = $r.Text | ConvertFrom-Json
  if ($j.errors) { Fail "GraphQL -> $(@($j.errors | ForEach-Object { $_.message }) -join '; ')" }
  return $j.data
}
# GitLab: /projects/group%2Fname   GitHub: /repos/owner/name
function P { if (IsGitHub) { "/repos/$(Get-ProjectPath)" } else { "/projects/$(Esc (Get-ProjectPath))" } }

function Save-Token([string]$Token) {
  $t = "$Token".Trim()
  if (-not $t) { return @{ Ok = $false; Text = 'No token given. Paste it and try again.' } }
  $r = Send-Http 'GET' "$(Get-ApiBase)/user" $t $null
  if ($r.Status -eq 401) { return @{ Ok = $false; Text = "$(Get-HostName) rejected this token (expired, revoked or not copied completely). Nothing was saved." } }
  if (-not $r.Ok) { return @{ Ok = $false; Text = "Could not check the token with $(Get-HostName) ($($r.Status)). Check the network / VPN. Nothing was saved." } }
  $me = $r.Text | ConvertFrom-Json
  New-Item -ItemType Directory -Force (ConfigDir) | Out-Null
  $file = Get-TokenFile
  [IO.File]::WriteAllText($file, "$t`n", (New-Object Text.UTF8Encoding($false)))
  if (-not $env:USERPROFILE -and (Get-Command chmod -ErrorAction SilentlyContinue)) { & chmod 600 $file }
  $name = if (IsGitHub) { $me.login } else { $me.username }
  return @{ Ok = $true; Text = "Saved to $file`nUser on $(Get-HostName): $name" }
}

# ---------- server functions: the same shape for GitLab and GitHub ----------
# issue  = Number, Title, Open, Labels, Assignees, Author, Due, Milestone, Url, Body, Confidential, CommentCount
# change = Number, Title, Branch, Url, Draft, Labels, NodeId   (MR on GitLab, PR on GitHub)
function Get-Me { $u = Api 'GET' '/user'; if (IsGitHub) { @{ Name = $u.login; Id = $u.id } } else { @{ Name = $u.username; Id = $u.id } } }

function Get-Issue([string]$n) {
  $i = Api 'GET' "$(P)/issues/$n"
  if (IsGitHub) {
    if ($i.pull_request) { Fail "#$n is a pull request, not an issue" }
    return @{ Number = $i.number; Title = $i.title; Open = ($i.state -eq 'open'); Labels = @($i.labels | ForEach-Object { $_.name } | Where-Object { $_ })
      Assignees = @($i.assignees | ForEach-Object { $_.login } | Where-Object { $_ }); Author = $i.user.login; Due = $(if ($i.milestone) { $i.milestone.due_on } else { $null }); Milestone = $(if ($i.milestone) { $i.milestone.title } else { $null })
      Url = $i.html_url; Body = $i.body; Confidential = $false; CommentCount = [int]$i.comments }
  }
  return @{ Number = $i.iid; Title = $i.title; Open = ($i.state -eq 'opened'); Labels = @($i.labels | Where-Object { $_ })
    Assignees = @($i.assignees | ForEach-Object { $_.username } | Where-Object { $_ }); Author = $i.author.username; Due = $i.due_date; Milestone = $(if ($i.milestone) { $i.milestone.title } else { $null })
    Url = $i.web_url; Body = $i.description; Confidential = [bool]$i.confidential; CommentCount = 0 }
}
# The newest comments, oldest first.
function Get-Comments($Issue) {
  if (IsGitHub) {
    $page = [Math]::Max(1, [Math]::Ceiling($Issue.CommentCount / 100))
    $c = @(ApiList "$(P)/issues/$($Issue.Number)/comments?per_page=100&page=$page" | Select-Object -Last 20 | ForEach-Object { @{ by = $_.user.login; at = "$($_.created_at)"; body = $_.body } })
  } else {
    $c = @(ApiList "$(P)/issues/$($Issue.Number)/notes?sort=desc&order_by=created_at&per_page=100" | Where-Object { -not $_.system } | Select-Object -First 20 | ForEach-Object { @{ by = $_.author.username; at = "$($_.created_at)"; body = $_.body } })
    [array]::Reverse($c)
  }
  foreach ($x in $c) { [ordered]@{ by = $x.by; at = $x.at; body = $x.body } }
}
function Get-StatusLabels($Labels, [string]$Keep) { @($Labels) | Where-Object { $_ -and ([string]$_).StartsWith($StatusPrefix) -and $_ -ne $Keep } }
# $Kind: issue | change. Adds $Add and removes the other status labels.
function Set-Status([string]$Kind, $Item, [string]$Add) {
  $remove = @(Get-StatusLabels $Item.Labels $Add)
  if (IsGitHub) {   # a pull request is labelled through the issues API too
    Api 'POST' "$(P)/issues/$($Item.Number)/labels" ([ordered]@{ labels = @($Add) }) | Out-Null
    foreach ($l in $remove) { Api 'DELETE' "$(P)/issues/$($Item.Number)/labels/$(Esc $l)" $null @(404) | Out-Null }
    return
  }
  $path = if ($Kind -eq 'issue') { 'issues' } else { 'merge_requests' }
  Api 'PUT' "$(P)/$path/$($Item.Number)" ([ordered]@{ add_labels = $Add; remove_labels = ($remove -join ',') }) | Out-Null
}

function ConvertTo-Change($m) {
  if (IsGitHub) { return @{ Number = $m.number; Title = $m.title; Branch = $m.head.ref; Url = $m.html_url; Draft = [bool]$m.draft; Labels = @($m.labels | ForEach-Object { $_.name } | Where-Object { $_ }); NodeId = $m.node_id } }
  return @{ Number = $m.iid; Title = $m.title; Branch = $m.source_branch; Url = $m.web_url; Draft = [bool]$m.draft; Labels = @($m.labels | Where-Object { $_ }); NodeId = $null }
}
function Find-Change([string]$n) {
  $closes = "(?i)(Closes|Fixes|Resolves|Related to) #$n\b"
  if (IsGitHub) {
    for ($page = 1; $page -le 5; $page++) {
      $all = @(ApiList "$(P)/pulls?state=open&per_page=100&page=$page")
      $m = $all | Where-Object { ([string]$_.body) -match $closes -or ([string]$_.head.ref).StartsWith("$n-") } | Select-Object -First 1
      if ($m) { return ConvertTo-Change $m }
      if ($all.Count -lt 100) { break }
    }
    return $null
  }
  $m = ApiList "$(P)/merge_requests?state=opened&search=$(Esc ('#' + $n))&in=description&per_page=50" | Where-Object { ([string]$_.description) -match $closes } | Select-Object -First 1
  if (-not $m) { $m = ApiList "$(P)/issues/$n/related_merge_requests" | Where-Object { $_.state -eq 'opened' } | Select-Object -First 1 }
  if ($m) { return ConvertTo-Change $m }
  return $null
}
function Find-Branch([string]$n) {
  if (IsGitHub) { $b = @(ApiList "$(P)/git/matching-refs/heads/$n-"); if ($b.Count) { return ($b[0].ref -replace '^refs/heads/', '') }; return $null }
  $b = @(ApiList "$(P)/repository/branches?search=$(Esc ('^' + $n + '-'))")
  if ($b.Count) { return $b[0].name }
  return $null
}
function New-Branch([string]$Name) {
  if (IsGitHub) {
    $sha = (Api 'GET' "$(P)/git/ref/heads/$BaseBranch").object.sha
    Api 'POST' "$(P)/git/refs" ([ordered]@{ ref = "refs/heads/$Name"; sha = $sha }) | Out-Null
  } else { Api 'POST' "$(P)/repository/branches?branch=$(Esc $Name)&ref=$(Esc $BaseBranch)" | Out-Null }
}

# Reviewers: --reviewer > env ISSUE_FLOW_REVIEWER > file reviewer(.txt) > defaultReviewer in issue-flow.json > none
function Get-ReviewerNames {
  $raw = $script:ReviewerArg
  if (-not $raw) { $raw = $env:ISSUE_FLOW_REVIEWER }
  if (-not $raw) {
    $f = @('reviewer', 'reviewer.txt') | ForEach-Object { Join-Path (ConfigDir) $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($f) { $raw = [IO.File]::ReadAllText($f).TrimStart([char]0xFEFF) }
  }
  if (-not $raw) { $raw = [string]$Config.defaultReviewer }
  "$raw" -split '[\s,]+' | ForEach-Object { $_ -replace '^@', '' } | Where-Object { $_ } | Select-Object -Unique
}
# Checks that every reviewer exists, before anything is written.
function Get-Reviewers {
  foreach ($name in @(Get-ReviewerNames)) {
    if (IsGitHub) { $u = Api 'GET' "/users/$(Esc $name)" $null @(404); if (-not $u) { Fail "User @$name not found" }; @{ Name = $u.login; Id = $u.id } }
    else { $u = ApiList "/users?username=$(Esc $name)" | Select-Object -First 1; if (-not $u) { Fail "User @$name not found" }; @{ Name = $u.username; Id = $u.id } }
  }
}
function Set-Reviewers($Change, $Reviewers, $Me, [bool]$Replace) {
  if (IsGitHub) {
    $names = @($Reviewers | Where-Object { $_ -and $_.Name -ne $Me.Name } | ForEach-Object { $_.Name })   # GitHub refuses the author as reviewer
    if ($Replace) {
      $old = @((Api 'GET' "$(P)/pulls/$($Change.Number)/requested_reviewers").users | ForEach-Object { $_.login } | Where-Object { $_ -and $names -notcontains $_ })
      if ($old.Count) { Api 'DELETE' "$(P)/pulls/$($Change.Number)/requested_reviewers" ([ordered]@{ reviewers = $old }) | Out-Null }
    }
    if ($names.Count) { Api 'POST' "$(P)/pulls/$($Change.Number)/requested_reviewers" ([ordered]@{ reviewers = $names }) | Out-Null }
    return
  }
  Api 'PUT' "$(P)/merge_requests/$($Change.Number)" ([ordered]@{ reviewer_ids = @($Reviewers | Where-Object { $_ } | ForEach-Object { $_.Id }) }) | Out-Null
}
function New-Change($Issue, [string]$Branch, [bool]$Draft, [string]$Status, $Me, $Reviewers) {
  if (IsGitHub) {
    $m = Api 'POST' "$(P)/pulls" ([ordered]@{ title = $Issue.Title; head = $Branch; base = $BaseBranch; body = "Closes #$($Issue.Number)"; draft = $Draft })
    $c = ConvertTo-Change $m
    if ($script:DryRun) { $c.Number = 0 }
    Api 'POST' "$(P)/issues/$($c.Number)/assignees" ([ordered]@{ assignees = @($Me.Name) }) | Out-Null
    Set-Status 'change' $c $Status
    Set-Reviewers $c $Reviewers $Me $false
    return $c
  }
  $title = if ($Draft) { "Draft: $($Issue.Title)" } else { $Issue.Title }
  $m = Api 'POST' "$(P)/merge_requests" ([ordered]@{
    source_branch = $Branch; target_branch = $BaseBranch; title = $title; description = "Closes #$($Issue.Number)"; assignee_id = $Me.Id
    reviewer_ids = @($Reviewers | Where-Object { $_ } | ForEach-Object { $_.Id }); labels = $Status; remove_source_branch = $true })
  return ConvertTo-Change $m
}
$DraftPrefix = '^(Draft:|\[Draft\]|\(Draft\))\s*'
function Set-Draft($Change, [bool]$Draft) {
  if (IsGitHub) {
    if ($Change.Draft -eq $Draft) { return }
    $m = if ($Draft) { 'convertPullRequestToDraft' } else { 'markPullRequestReadyForReview' }
    GraphQL "mutation(`$id: ID!) { $m(input: {pullRequestId: `$id}) { pullRequest { isDraft } } }" ([ordered]@{ id = $Change.NodeId }) $true | Out-Null
    return
  }
  $isDraft = $Change.Title -match $DraftPrefix
  if ([bool]$isDraft -eq $Draft) { return }
  $title = if ($Draft) { "Draft: $($Change.Title)" } else { $Change.Title -replace $DraftPrefix, '' }
  Api 'PUT' "$(P)/merge_requests/$($Change.Number)" ([ordered]@{ title = $title }) | Out-Null
}
# Unresolved review threads, with file:line when they are on the diff.
function Get-Feedback($Change) {
  if (IsGitHub) {
    $owner, $name = (Get-ProjectPath) -split '/', 2
    $cursor = $null
    do {
      $d = GraphQL 'query($o:String!,$n:String!,$k:Int!,$c:String){ repository(owner:$o,name:$n){ pullRequest(number:$k){ reviewThreads(first:100,after:$c){ pageInfo{hasNextPage endCursor} nodes{ isResolved path line originalLine comments(first:50){ nodes{ author{login} body } } } } } } }' ([ordered]@{ o = $owner; n = $name; k = $Change.Number; c = $cursor }) $false
      $t = $d.repository.pullRequest.reviewThreads
      foreach ($x in @($t.nodes | Where-Object { $_ -and -not $_.isResolved })) {
        $line = if ($x.line) { $x.line } else { $x.originalLine }
        [ordered]@{ where = "$($x.path)$(if ($line) { ":$line" })"; text = (@($x.comments.nodes | ForEach-Object { "$($_.author.login): $($_.body)" }) -join "`n") }
      }
      $cursor = $t.pageInfo.endCursor
    } while ($t.pageInfo.hasNextPage)
    # "Request changes" with a summary has no thread of its own: show each reviewer's latest one.
    $reviews = @(ApiList "$(P)/pulls/$($Change.Number)/reviews?per_page=100" | Where-Object { @('CHANGES_REQUESTED', 'APPROVED', 'DISMISSED') -contains $_.state })
    foreach ($g in @($reviews | Group-Object { $_.user.login })) { $r = $g.Group[-1]; if ($r.state -eq 'CHANGES_REQUESTED' -and $r.body) { [ordered]@{ where = ''; text = "$($r.user.login): $($r.body)" } } }
    return
  }
  foreach ($d in @(ApiList "$(P)/merge_requests/$($Change.Number)/discussions?per_page=100")) {
    $notes = @(@($d.notes) | Where-Object { $_ -and -not $_.system })
    if (-not $notes.Count -or $notes[0].resolvable -eq $false -or -not @($notes | Where-Object { -not $_.resolved }).Count) { continue }
    $pos = $notes[0].position; $where = ''
    if ($pos) {
      $where = if ($pos.new_path) { $pos.new_path } else { $pos.old_path }
      if ($pos.new_line) { $where += ":$($pos.new_line)" } elseif ($pos.old_line) { $where += ":$($pos.old_line)" }
    }
    [ordered]@{ where = $where; text = (@($notes | ForEach-Object { "$($_.author.username): $($_.body)" }) -join "`n") }
  }
}

# "<n>-<title>" (GitLab's own rule, also used on GitHub)
function Get-BranchName($Issue) {
  if ($Issue.Confidential) { return "$($Issue.Number)-confidential-issue" }
  $slug = ([string]$Issue.Title).Normalize([Text.NormalizationForm]::FormD) -replace '[̀-ͯ]', ''
  $slug = ($slug -replace '[^a-zA-Z0-9\-_]+', '-' -replace '-{2,}', '-' -replace '^-|-$', '').ToLowerInvariant()
  $name = if ($slug) { "$($Issue.Number)-$slug" } else { "$($Issue.Number)-issue" }
  if ($name.Length -gt 100) { $name = $name.Substring(0, 100) }
  return $name.TrimEnd('-')
}

# ---------- local checks ----------
# The tree hash git would commit right now (tracked + untracked, .gitignore respected), built in a temp index.
# Committing does not change it; any edit does.
function Get-Fingerprint {
  $idx = Join-Path ([IO.Path]::GetTempPath()) "issue-flow-$PID.idx"
  $real = Join-Path (Get-GitDir) 'index'
  $old = $env:GIT_INDEX_FILE
  try {
    if (Test-Path -LiteralPath $real) { Copy-Item -LiteralPath $real $idx -Force }
    $env:GIT_INDEX_FILE = $idx
    & $GitExe add -A 2>$null | Out-Null
    $tree = (& $GitExe write-tree 2>$null | Select-Object -First 1)
  } finally {
    $env:GIT_INDEX_FILE = $old
    Remove-Item $idx -Force -ErrorAction SilentlyContinue
  }
  if (-not $tree) { Fail 'Not inside a git repository' }
  return ([string]$tree).Trim().Substring(0, 12)
}
function Get-BranchFiles {
  $mb = (Git merge-base "origin/$BaseBranch" HEAD).Trim()
  $base = if ($mb) { $mb } else { 'HEAD' }
  $names = @((Git diff --name-only $base) -split "`n") + @((Git ls-files --others --exclude-standard) -split "`n")
  $names | Where-Object { $_ } | ForEach-Object { $_ -replace '\\', '/' } | Select-Object -Unique
}

# ---------- related tests ----------
# Each changed file belongs to the nearest folder with a build file; each such folder is one run, so a mixed
# repository (for example a Java API + a Node front end) gives several runs. .claude/issue-flow.json "tests" overrides it all.
$IsWin = $env:OS -eq 'Windows_NT'
function Get-Stack([string]$Dir) {
  $d = if ($Dir) { $Dir } else { '.' }
  $has = { param($f) Test-Path (Join-Path $d $f) }
  if (& $has 'pom.xml') { return 'maven' }
  if ((& $has 'build.gradle') -or (& $has 'build.gradle.kts')) { return 'gradle' }
  if (& $has 'go.mod') { return 'go' }
  if (& $has 'Cargo.toml') { return 'rust' }
  if ((& $has '*.csproj') -or (& $has '*.sln') -or (& $has '*.slnx')) { return 'dotnet' }
  if ((& $has 'pyproject.toml') -or (& $has 'pytest.ini') -or (& $has 'setup.py') -or (& $has 'requirements.txt')) { return 'python' }
  if (& $has 'composer.json') { return 'php' }
  if (& $has 'Gemfile') { return 'ruby' }
  if (& $has 'package.json') { return 'node' }
  return $null
}
function Get-Root([string]$File) {
  $d = Split-Path $File -Parent
  while ($true) {
    $s = Get-Stack $d
    if ($s) { return @{ Dir = $(if ($d) { $d -replace '\\', '/' } else { '.' }); Stack = $s } }
    if (-not $d) { return $null }
    $d = Split-Path $d -Parent
  }
}
# Only plain names go into a command line.
function IsSafe([string]$s) { $s -match '^[\w./@][\w./@+\-]*$' }
function Get-TestPattern([string]$Stack, [string]$Base) {
  $b = [regex]::Escape($Base)
  switch ($Stack) {
    'maven' { "^$b\w*(Test|Tests|IT|Spec)\.(java|kt|groovy|scala)$" }
    'gradle' { "^$b\w*(Test|Tests|IT|Spec)\.(java|kt|groovy|scala)$" }
    'node' { "^$b\.(test|spec)\.[cm]?[jt]sx?$" }
    'python' { "^(test_$b|${b}_test)\.py$" }
    'dotnet' { "^$b(Tests?|Specs?)\.cs$" }
    'php' { "^${b}Test\.php$" }
    'ruby' { "^${b}_(spec|test)\.rb$" }
  }
}
$TestFile = @{
  maven = '(Test|Tests|IT|Spec)\.(java|kt|groovy|scala)$'; gradle = '(Test|Tests|IT|Spec)\.(java|kt|groovy|scala)$'; node = '\.(test|spec)\.[cm]?[jt]sx?$'
  python = '(^|/)(test_[^/]+|[^/]+_test)\.py$'; dotnet = '(Tests?|Specs?)\.cs$'; php = 'Test\.php$'; ruby = '_(spec|test)\.rb$'
}
$SourceExt = @{
  maven = '\.(java|kt|groovy|scala)$'; gradle = '\.(java|kt|groovy|scala)$'; node = '\.([cm]?[jt]sx?|vue|svelte)$'; python = '\.py$'; dotnet = '\.cs$'
  php = '\.php$'; ruby = '\.rb$'; go = '\.go$'; rust = '\.rs$'
}
function Get-NodeRunner([string]$Dir) {
  $p = $null
  try { $p = [IO.File]::ReadAllText((Resolve-Path (Join-Path $Dir 'package.json')).ProviderPath) | ConvertFrom-Json } catch {}
  $deps = @(); foreach ($k in 'dependencies', 'devDependencies') { if ($p.$k) { $deps += @($p.$k.PSObject.Properties | ForEach-Object { $_.Name }) } }
  $exec = 'npx'; $all = 'npm test'
  if (Test-Path (Join-Path $Dir 'pnpm-lock.yaml')) { $exec = 'pnpm exec'; $all = 'pnpm test' }
  elseif (Test-Path (Join-Path $Dir 'yarn.lock')) { $exec = 'yarn'; $all = 'yarn test' }
  elseif ((Test-Path (Join-Path $Dir 'bun.lockb')) -or (Test-Path (Join-Path $Dir 'bun.lock'))) { $exec = 'bunx'; $all = 'bun run test' }
  $run = if ($deps -contains 'vitest') { "$exec vitest run" } elseif ($deps -contains 'jest') { "$exec jest" } elseif ($deps -contains 'mocha') { "$exec mocha" } else { '' }
  return @{ Run = $run; All = $all }
}
# @{ Dir; Command; All } for one run. Command is '' when the stack cannot pick tests: then All is the choice.
function Get-TestCommand([string]$Stack, [string]$Dir, [string[]]$Tests) {
  $rel = @($Tests | Where-Object { $_ } | ForEach-Object { if ($Dir -ne '.' -and $_.StartsWith("$Dir/")) { $_.Substring($Dir.Length + 1) } else { $_ } })
  $names = @($rel | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } | Select-Object -Unique)
  $n = $rel.Count
  switch ($Stack) {
    'maven' {
      $w = if ($IsWin) { 'mvnw.cmd' } else { 'mvnw' }; $cwd = $Dir; $x = 'mvn'
      if (Test-Path (Join-Path $Dir $w)) { $x = "./$w" } elseif (Test-Path $w) { $cwd = '.'; $x = "./$w -f $Dir/pom.xml" }
      return @{ Dir = $cwd; All = "$x test"; Command = $(if ($n) { "$x test `"-Dtest=$($names -join ',')`" -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false" } else { '' }) }
    }
    'gradle' {
      $w = if ($IsWin) { 'gradlew.bat' } else { 'gradlew' }; $cwd = $Dir; $task = 'test'; $x = 'gradle'
      if (Test-Path (Join-Path $Dir $w)) { $x = "./$w" } elseif (Test-Path $w) { $cwd = '.'; $x = "./$w"; $task = ":$($Dir -replace '/', ':'):test" }
      return @{ Dir = $cwd; All = "$x $task"; Command = $(if ($n) { "$x $task " + (@($names | ForEach-Object { "--tests `"*$_`"" }) -join ' ') } else { '' }) }
    }
    'node' { $r = Get-NodeRunner $Dir; return @{ Dir = $Dir; All = $r.All; Command = $(if ($n -and $r.Run) { "$($r.Run) $($rel -join ' ')" } else { '' }) } }
    'python' { return @{ Dir = $Dir; All = 'python -m pytest'; Command = $(if ($n) { "python -m pytest $($rel -join ' ')" } else { '' }) } }
    'go' { return @{ Dir = $Dir; All = 'go test ./...'; Command = $(if ($n) { "go test $($rel -join ' ')" } else { '' }) } }
    'rust' { return @{ Dir = $Dir; All = 'cargo test'; Command = '' } }
    'dotnet' { return @{ Dir = $Dir; All = 'dotnet test'; Command = $(if ($n) { "dotnet test --filter `"$((@($names | ForEach-Object { "FullyQualifiedName~$_" })) -join '|')`"" } else { '' }) } }
    'php' { return @{ Dir = $Dir; All = 'vendor/bin/phpunit'; Command = $(if ($n) { "vendor/bin/phpunit --filter `"$($names -join '|')`"" } else { '' }) } }
    'ruby' {
      $sp = @($rel | Where-Object { $_ -match '_spec\.rb$' })
      $all = if (Test-Path (Join-Path $Dir 'spec')) { 'bundle exec rspec' } else { 'bundle exec rake test' }
      return @{ Dir = $Dir; All = $all; Command = $(if ($sp.Count -and $sp.Count -eq $n) { "bundle exec rspec $($sp -join ' ')" } else { '' }) }
    }
  }
}
function Get-RelatedRuns {
  $changed = @(Get-BranchFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
  $o = $Config.tests
  if ($o -and $o.all) {   # the team's own commands; {tests} = changed test files
    return [ordered]@{ dir = '.'; stack = 'custom'; tests = @(); command = [string]$o.related; all = [string]$o.all }
  }
  $files = @((Git ls-files --cached --others --exclude-standard) -split "`n" | Where-Object { $_ })
  $groups = [ordered]@{}
  foreach ($f in $changed) {
    $r = Get-Root $f
    if (-not $r -or $f -notmatch $SourceExt[$r.Stack]) { continue }
    $k = "$($r.Dir)|$($r.Stack)"
    if (-not $groups.Contains($k)) { $groups[$k] = @{ Dir = $r.Dir; Stack = $r.Stack; Changed = New-Object System.Collections.Generic.List[string] } }
    $groups[$k].Changed.Add($f)
  }
  foreach ($g in $groups.Values) {
    $tests = New-Object System.Collections.Generic.SortedSet[string]([StringComparer]::Ordinal)
    $inside = if ($g.Dir -eq '.') { $files } else { @($files | Where-Object { $_.StartsWith("$($g.Dir)/") }) }
    foreach ($f in $g.Changed) {
      if ($g.Stack -eq 'go') { $p = (Split-Path $f -Parent) -replace '\\', '/'; if ($g.Dir -ne '.') { $p = $p.Substring([Math]::Min($p.Length, $g.Dir.Length)).TrimStart('/') }; [void]$tests.Add($(if ($p) { "./$p" } else { '.' })); continue }
      if ($g.Stack -eq 'rust') { continue }
      if ($f -match $TestFile[$g.Stack]) { [void]$tests.Add($f); continue }
      $pat = Get-TestPattern $g.Stack ([IO.Path]::GetFileNameWithoutExtension($f))
      foreach ($t in $inside) { if ((Split-Path $t -Leaf) -cmatch $pat -and (Test-Path -LiteralPath $t)) { [void]$tests.Add($t) } }
    }
    $list = @($tests)
    $usable = if (@($list | Where-Object { -not (IsSafe $_) }).Count) { @() } else { $list }
    $c = Get-TestCommand $g.Stack $g.Dir $usable
    [ordered]@{ dir = $c.Dir; stack = $g.Stack; tests = $list; command = $c.Command; all = $c.All }
  }
}

# ---------- commands ----------
$Commands = [ordered]@{
  'set-token' = {
    if ([Console]::IsInputRedirected) {
      [Console]::Error.Write('Paste the token and press Enter (this terminal cannot hide it): ')
      $t = [Console]::In.ReadLine()
    } else {
      $sec = Read-Host "Token for $(Get-HostName) ($(Get-TokenHelp))" -AsSecureString
      $t = (New-Object System.Net.NetworkCredential('', $sec)).Password
    }
    $r = Save-Token $t
    if ($r.Ok) { $r.Text } else { [Console]::Error.WriteLine($r.Text); $script:ExitCode = 1 }
  }
  'check' = {
    $me = Get-Me
    $proj = Api 'GET' (P)
    $rev = @(Get-Reviewers)
    $labels = @(if (IsGitHub) { ApiList "$(P)/labels?per_page=100" | ForEach-Object { $_.name } } else { ApiList "$(P)/labels?search=$(Esc $StatusPrefix)&per_page=100&include_ancestor_groups=true" | ForEach-Object { $_.name } })
    ToJson ([ordered]@{ provider = (Get-Provider); host = (Get-HostName); token_user = $me.Name; project = (Get-ProjectPath); default_branch = $proj.default_branch; base_branch = $BaseBranch
      reviewers = @($rev | ForEach-Object { $_.Name }); in_progress_label_exists = ($labels -contains $LabelInProgress); awaiting_review_label_exists = ($labels -contains $LabelAwaitingReview) })
  }
  'issue' = {
    param($n)
    $i = Get-Issue $n
    ToJson ([ordered]@{ number = $i.Number; title = $i.Title; open = $i.Open; labels = @($i.Labels); assignees = @($i.Assignees); author = $i.Author; due_date = $i.Due; milestone = $i.Milestone
      url = $i.Url; branch = (Get-BranchName $i); body = $i.Body; comments = @(Get-Comments $i) })
  }
  'progress' = {
    param($n)
    $i = Get-Issue $n
    if (-not $i.Open) { Fail "Issue #$n is closed" }
    Set-Status 'issue' $i $LabelInProgress
    ToJson ([ordered]@{ issue = $i.Url; status = $LabelInProgress; branch = (Get-BranchName $i) })
  }
  # In-progress label + branch + Draft MR. GitHub cannot open a PR on a branch without commits: there it stops at the branch.
  'start' = {
    param($n)
    $i = Get-Issue $n
    if (-not $i.Open) { Fail "Issue #$n is closed" }
    $me = Get-Me
    $rev = @(Get-Reviewers)
    $branch = Find-Branch $n
    $c = Find-Change $n
    if ($c) { $branch = $c.Branch }
    Set-Status 'issue' $i $LabelInProgress
    if (-not $branch) { $branch = Get-BranchName $i; New-Branch $branch }
    if (-not $c -and -not (IsGitHub)) { $c = New-Change $i $branch $true $LabelInProgress $me $rev }
    ToJson ([ordered]@{ issue = $i.Url; branch = $branch; change = $(if ($c) { $c.Url } else { $null }); change_number = $(if ($c) { $c.Number } else { $null }); reviewers = @($rev | ForEach-Object { $_.Name })
      note = $(if (-not $c) { 'GitHub opens the PR after the first push: /submit-review does it' } else { $null }) })
  }
  # After the push: open or update the MR / PR. Default = ready + awaiting review; --draft = Draft + in progress.
  'open-change' = {
    param($n)
    $branch = (Git branch --show-current).Trim()
    if (-not $branch -or @($BaseBranch, 'main', 'master') -contains $branch) { Fail 'Check out the issue branch first' }
    if (-not (Git ls-remote --heads origin $branch).Trim()) { Fail "Branch $branch is not on the server yet: push it first" }
    $draft = [bool]$script:Draft
    $status = if ($draft) { $LabelInProgress } else { $LabelAwaitingReview }
    $i = Get-Issue $n
    $c = Find-Change $n
    if ($c -and $c.Branch -ne $branch) { Fail "Issue #$n already has a change from branch $($c.Branch), but $branch is checked out" }
    $me = Get-Me
    $rev = @(Get-Reviewers)
    $created = -not $c
    if ($created) { $c = New-Change $i $branch $draft $status $me $rev }
    else { Set-Status 'change' $c $status; Set-Draft $c $draft; if ((IsGitHub) -and -not $draft) { Set-Reviewers $c $rev $me $false } }
    Set-Status 'issue' $i $status
    ToJson ([ordered]@{ issue = $i.Url; change = $c.Url; change_number = $c.Number; created = $created; draft = $draft; status = $status; reviewers = @($rev | ForEach-Object { $_.Name }) })
  }
  'find-change' = {
    param($n)
    $c = Find-Change $n
    if ($c) { ToJson ([ordered]@{ number = $c.Number; title = $c.Title; branch = $c.Branch; url = $c.Url; draft = $c.Draft }) } else { 'null' }
  }
  # Rejected or pulled back: in-progress label, back to Draft.
  'reopen' = {
    param($n)
    $i = Get-Issue $n
    $c = Find-Change $n
    if (-not $c) { Fail "No open MR / PR found for issue #$n" }
    Set-Status 'issue' $i $LabelInProgress
    Set-Status 'change' $c $LabelInProgress
    Set-Draft $c $true
    ToJson ([ordered]@{ issue = $i.Url; change = $c.Url; branch = $c.Branch; status = $LabelInProgress })
  }
  'feedback' = {
    param($n)
    $c = Find-Change $n
    if (-not $c) { Fail "No open MR / PR found for issue #$n" }
    ToJson ([ordered]@{ change = $c.Url; branch = $c.Branch; unresolved = @(Get-Feedback $c) })
  }
  'set-reviewer' = {
    param($n)
    $c = Find-Change $n
    if (-not $c) { Fail "No open MR / PR found for issue #$n" }
    $rev = @(Get-Reviewers)
    if (-not $rev.Count) { Fail 'No reviewer given: --reviewer name, reviewer.txt, or defaultReviewer in .claude/issue-flow.json' }
    Set-Reviewers $c $rev (Get-Me) $true
    ToJson ([ordered]@{ change = $c.Url; reviewers = @($rev | ForEach-Object { $_.Name }) })
  }
  'fingerprint' = { Get-Fingerprint }
  # Tests for what this branch changes, one run per project folder (see Get-RelatedRuns).
  'related-tests' = {
    $runs = @(Get-RelatedRuns)
    $issue = if ($Config.tests -and $Config.tests.issue) { [string]$Config.tests.issue } else { '' }
    ToJson ([ordered]@{ runs = $runs; issue_command = $issue; note = $(if (-not $runs.Count) { 'No known build file covers the changed files: use the test command in CLAUDE.md / README' } else { $null }) })
  }
  # Writes .claude/issue-flow.json with the detected server and base branch (never overwrites).
  'init' = {
    if (-not $Top) { Fail 'Not inside a git repository' }
    if (Test-Path -LiteralPath $ConfigFile) { return (ToJson ([ordered]@{ created = $false; file = $ConfigFile })) }
    $json = ToJson ([ordered]@{ provider = ''; host = ''; baseBranch = $BaseBranch; defaultReviewer = ''
      labels = [ordered]@{ prefix = 'Status'; inProgress = 'Status: In progress'; awaitingReview = 'Status: Awaiting review' }
      tests = [ordered]@{ related = ''; all = ''; issue = '' } })
    New-Item -ItemType Directory -Force (Split-Path $ConfigFile -Parent) | Out-Null
    [IO.File]::WriteAllText($ConfigFile, "$json`n", (New-Object Text.UTF8Encoding($false)))
    ToJson ([ordered]@{ created = $true; file = $ConfigFile; provider = (Get-Provider); host = (Get-HostName); baseBranch = $BaseBranch })
  }
  'base-behind' = {
    Git fetch origin $BaseBranch | Out-Null
    $k = 0; [void][int]::TryParse((Git rev-list --count "HEAD..origin/$BaseBranch").Trim(), [ref]$k)
    ToJson ([ordered]@{ base = $BaseBranch; behind = $k })
  }
  # Was exactly the current code reviewed, with no high finding left open?
  'review-status' = {
    param($n)
    $f = Join-Path (Join-Path (Get-GitDir) 'claude-flow') "review-$n.json"
    if (-not (Test-Path -LiteralPath $f)) { return (ToJson ([ordered]@{ status = 'missing'; file = $f })) }
    $r = $null
    try { $r = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $f).ProviderPath) | ConvertFrom-Json } catch {}
    if (-not $r) { return (ToJson ([ordered]@{ status = 'broken'; file = $f })) }
    $now = Get-Fingerprint
    $open = @(@($r.findings) | Where-Object { $_ -and $_.severity -eq 'high' -and @('fixed', 'skip') -notcontains $_.decision })
    $status = if ($r.fingerprint -ne $now) { 'stale' } elseif ($open.Count) { 'high-open' } else { 'ok' }
    ToJson ([ordered]@{ status = $status; reviewed = $r.fingerprint; current = $now; at = $r.at; open_high = @($open | ForEach-Object { $_.title }) })
  }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # dot-sourced: functions only

# ---------- arguments ----------
$rest = New-Object System.Collections.Generic.List[string]
for ($k = 0; $k -lt $args.Count; $k++) {
  $a = [string]$args[$k]
  switch ($a) {
    '--dry-run' { $script:DryRun = $true }
    '--draft' { $script:Draft = $true }
    '--project' { $k++; $script:ProjectArg = [string]$args[$k] }
    '--reviewer' { $k++; $script:ReviewerArg = [string]$args[$k] }
    default {
      if ($a -match '^https?://([^/]+)/(.+?)/(?:-/)?(?:issues|work_items)/(\d+)') { $script:UrlHost = $Matches[1]; if (-not $script:ProjectArg) { $script:ProjectArg = $Matches[2] }; $rest.Add($Matches[3]) }
      else { $rest.Add($a) }
    }
  }
}
$cmd = if ($rest.Count) { $rest[0] } else { '' }
$num = if ($rest.Count -gt 1) { $rest[1] } else { '' }
$NoIssueNeeded = @('init', 'set-token', 'check', 'fingerprint', 'related-tests', 'base-behind')
$script:ExitCode = 0
try {
  if (-not $Commands.Contains($cmd)) { Fail ('Usage: issue-flow <' + (@($Commands.Keys) -join '|') + '> [n | issue URL] [--draft] [--reviewer a,b] [--project path] [--dry-run]') }
  if ($NoIssueNeeded -notcontains $cmd -and $num -notmatch '^\d+$') { Fail 'Issue number required' }
  if ($script:UrlHost -and $script:UrlHost -ne (Get-HostName)) { Fail "The issue is on $($script:UrlHost) but this repo uses $(Get-HostName)" }
  & $Commands[$cmd] $num
} catch {
  [Console]::Error.WriteLine('ERROR: ' + $_.Exception.Message); $script:ExitCode = 1
}
exit $script:ExitCode
