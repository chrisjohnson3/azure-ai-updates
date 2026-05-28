param(
  [Parameter(Mandatory = $true)]
  [string]$SourceHtml,

  [Parameter(Mandatory = $true)]
  [string]$ArchiveName,

  [Parameter(Mandatory = $true)]
  [string]$CommitMessage,

  [string]$RepoRoot = $PSScriptRoot,

  [string]$BackupRoot = "C:\Users\chrisjohn\OneDrive - Microsoft\Documents\Web Updates"
)

$ErrorActionPreference = "Stop"

function Fail($Message) {
  Write-Error $Message
  exit 1
}

function Assert-FullHtml($Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    Fail "Missing HTML file: $Path"
  }

  $item = Get-Item -LiteralPath $Path
  if ($item.Length -lt 10000) {
    Fail "HTML file is too small and may be a stub: $Path ($($item.Length) bytes)"
  }

  $html = Get-Content -LiteralPath $Path -Raw
  $required = @(
    '<title>Azure + AI Updates</title>',
    'id="updates"',
    'id="ai-updates"',
    'id="security-identity"',
    'id="follow-up"',
    'class="source-menu"'
  )

  foreach ($needle in $required) {
    if ($html -notlike "*$needle*") {
      Fail "HTML file missing required marker '$needle': $Path"
    }
  }

  if ($html -match 'http-equiv="refresh"|location\.replace\(') {
    Fail "HTML file appears to be a redirect stub: $Path"
  }

  if ($html -match '__COPY_FROM_SOURCE__|PLACEHOLDER') {
    Fail "HTML file contains placeholder text: $Path"
  }
}

function Copy-FullHtml($Source, $Destination) {
  $parent = Split-Path -Parent $Destination
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $resolvedSource = (Resolve-Path -LiteralPath $Source).Path
  $resolvedDestination = $Destination
  if (Test-Path -LiteralPath $Destination) {
    $resolvedDestination = (Resolve-Path -LiteralPath $Destination).Path
  }
  if ($resolvedSource -ne $resolvedDestination) {
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
  }
  Assert-FullHtml $Destination
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SourceHtml = (Resolve-Path -LiteralPath $SourceHtml).Path
$archivePath = Join-Path $RepoRoot ("updates\" + $ArchiveName)
$indexPath = Join-Path $RepoRoot "index.html"
$currentPath = Join-Path $RepoRoot "current.html"

Assert-FullHtml $SourceHtml

Copy-FullHtml $SourceHtml $indexPath
Copy-FullHtml $SourceHtml $currentPath
Copy-FullHtml $SourceHtml $archivePath

if (Test-Path -LiteralPath $BackupRoot) {
  Copy-FullHtml $SourceHtml (Join-Path $BackupRoot "index.html")
  Copy-FullHtml $SourceHtml (Join-Path $BackupRoot "current.html")
  Copy-FullHtml $SourceHtml (Join-Path $BackupRoot (($ArchiveName -replace '\.html$', '') + "-Updates.html"))
}

Push-Location $RepoRoot
try {
  $statusBefore = git --no-pager status --short
  Write-Output "Git status before commit:"
  if ($statusBefore) { $statusBefore } else { "clean" }

  git add index.html current.html ("updates/" + $ArchiveName) publish-update.ps1

  $staged = git diff --cached --name-only
  if (-not $staged) {
    Write-Output "NO_CHANGES"
    exit 0
  }

  git commit -m $CommitMessage
  git push origin main

  $localHead = (git rev-parse HEAD).Trim()
  $remoteLine = git ls-remote origin refs/heads/main
  $remoteHead = ($remoteLine -split "\s+")[0]

  if ($localHead -ne $remoteHead) {
    Fail "Push verification failed. Local HEAD $localHead does not match remote HEAD $remoteHead."
  }

  $statusAfter = git --no-pager status --short
  if ($statusAfter) {
    Fail "Repository is not clean after publish: $statusAfter"
  }

  Write-Output "PUBLISHED $localHead"
}
finally {
  Pop-Location
}
