param(
    [int]$DaysInactive = 3,
    
    [string]$Repo = "FRCTeam360/RainMaker26"
)

Write-Host "Finding stale branches in $Repo (inactive for $DaysInactive+ days, 0 commits ahead of main, no active PRs)..." -ForegroundColor Cyan
Write-Host ""

# Check if gh CLI is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Error: GitHub CLI (gh) is not installed." -ForegroundColor Red
    Write-Host "Install it with: choco install gh" -ForegroundColor Yellow
    exit 1
}

# Get current date
$cutoffDate = (Get-Date).AddDays(-$DaysInactive)

# Get all remote branches except main
Write-Host "Fetching branches from $Repo..." -ForegroundColor Yellow
try {
    $branchesJson = gh api "repos/$Repo/branches" --paginate 2>&1
    $branches = $branchesJson | ConvertFrom-Json | Where-Object { $_.name -ne 'main' }
} catch {
    Write-Host "Error fetching branches: $_" -ForegroundColor Red
    exit 1
}

$staleBranches = @()

foreach ($branch in $branches) {
    $branchName = $branch.name
    
    # Get last commit date from the branch object
    try {
        $commitInfo = gh api "repos/$Repo/commits/$($branch.commit.sha)" 2>&1 | ConvertFrom-Json
        $lastCommitDate = $commitInfo.commit.author.date
    } catch {
        Write-Host "Warning: Could not fetch commit info for $branchName" -ForegroundColor Yellow
        continue
    }
    
    $commitDate = [DateTime]::Parse($lastCommitDate)
    
    # Check if inactive
    if ($commitDate -gt $cutoffDate) {
        continue
    }
    
    # Check if 0 commits ahead of main
    try {
        $compareResult = gh api "repos/$Repo/compare/main...$branchName" 2>&1 | ConvertFrom-Json
        $aheadCount = $compareResult.ahead_by
    } catch {
        Write-Host "Warning: Could not compare $branchName with main" -ForegroundColor Yellow
        continue
    }
    
    if ($aheadCount -ne 0) {
        continue
    }
    
    # Check for PRs
    $prs = gh pr list --repo $Repo --head $branchName --state all --json number,state 2>$null | ConvertFrom-Json
    
    # Determine PR status
    $mergedPR = $prs | Where-Object { $_.state -eq "MERGED" } | Select-Object -First 1
    $openPR = $prs | Where-Object { $_.state -eq "OPEN" } | Select-Object -First 1
    $closedPR = $prs | Where-Object { $_.state -eq "CLOSED" } | Select-Object -First 1
    
    if ($mergedPR) {
        $prInfo = "#$($mergedPR.number) Merged"
    } elseif ($openPR) {
        $prInfo = "#$($openPR.number) Open"
    } elseif ($closedPR) {
        $prInfo = "#$($closedPR.number) Closed"
    } else {
        $prInfo = "No PR"
    }
    
    # This branch is stale
    $daysOld = [math]::Round(((Get-Date) - $commitDate).TotalDays, 0)
    $staleBranches += [PSCustomObject]@{
        Branch = $branchName
        LastCommit = $commitDate.ToString("yyyy-MM-dd")
        DaysOld = $daysOld
        PR = $prInfo
    }
}

if ($staleBranches.Count -eq 0) {
    Write-Host "No stale branches found!" -ForegroundColor Green
    exit 0
}

# Display results
Write-Host "Found $($staleBranches.Count) stale branch(es):" -ForegroundColor Yellow
Write-Host ""
$staleBranches | Sort-Object -Property DaysOld -Descending | Format-Table -AutoSize

Write-Host ""
Write-Host "To archive these branches, run:" -ForegroundColor Cyan
foreach ($branch in $staleBranches) {
    Write-Host "  .\Archive-GitBranch.ps1 -BranchName $($branch.Branch) -Repo $Repo" -ForegroundColor White
}
