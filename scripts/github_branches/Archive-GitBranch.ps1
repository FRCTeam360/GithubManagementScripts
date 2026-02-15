param(
    [Parameter(Mandatory=$true)]
    [string]$BranchName,
    
    [string]$Repo = "FRCTeam360/RainMaker26"
)

Write-Host "Archiving branch '$BranchName' in repository '$Repo'..." -ForegroundColor Cyan
Write-Host ""

# Check if gh CLI is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Error: GitHub CLI (gh) is not installed." -ForegroundColor Red
    Write-Host "Install it with: choco install gh" -ForegroundColor Yellow
    exit 1
}

# Get the branch SHA
Write-Host "Fetching branch information..." -ForegroundColor Yellow
try {
    $branchInfo = gh api "repos/$Repo/branches/$BranchName" 2>&1 | ConvertFrom-Json
    $branchSha = $branchInfo.commit.sha
    Write-Host "Found branch at commit: $($branchSha.Substring(0,7))" -ForegroundColor Green
} catch {
    Write-Host "Error: Could not find branch '$BranchName' in repository '$Repo'" -ForegroundColor Red
    exit 1
}

# Create tag
Write-Host "Creating archive tag..." -ForegroundColor Yellow
try {
    $tagData = @{
        tag = "archive/$BranchName"
        message = "Archive of branch $BranchName"
        object = $branchSha
        type = "commit"
    } | ConvertTo-Json
    
    $tagResult = $tagData | gh api "repos/$Repo/git/tags" -X POST --input - 2>&1 | ConvertFrom-Json
    $tagSha = $tagResult.sha
    
    # Create the reference
    $refData = @{
        ref = "refs/tags/archive/$BranchName"
        sha = $tagSha
    } | ConvertTo-Json
    
    $refData | gh api "repos/$Repo/git/refs" -X POST --input - 2>&1 | Out-Null
    Write-Host "Created tag: archive/$BranchName" -ForegroundColor Green
} catch {
    Write-Host "Error: Could not create tag - $_" -ForegroundColor Red
    exit 1
}

# Delete remote branch
Write-Host "Deleting remote branch..." -ForegroundColor Yellow
try {
    gh api "repos/$Repo/git/refs/heads/$BranchName" -X DELETE 2>&1 | Out-Null
    Write-Host "Deleted branch: $BranchName" -ForegroundColor Green
} catch {
    Write-Host "Error: Could not delete remote branch - $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Successfully archived branch '$BranchName'!" -ForegroundColor Green
Write-Host "Tag 'archive/$BranchName' has been created and branch has been deleted." -ForegroundColor Cyan

