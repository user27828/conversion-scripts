# PowerShell script to merge audio (.m4a) and video (.mp4) files using ffmpeg
# Assumes ffmpeg is installed and available in PATH
# This script runs merges in parallel for faster processing

param(
    [string]$Directory,
    [switch]$Help
)

if ($Help -or -not $PSBoundParameters.ContainsKey('Directory')) {
    Write-Host "Usage: .\merge-mp4-m4a.ps1 -Directory <path> [-Help]"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -Directory <path>  : Directory containing .m4a and .mp4 files to merge. If empty, uses current directory."
    Write-Host "  -Help              : Show this help message."
    Write-Host ""
    Write-Host "Description:"
    Write-Host "  Merges audio (.m4a) and video (.mp4) files with matching basenames into single video files."
    Write-Host "  Uses ffmpeg to combine them, running merges in parallel (limited by CPU cores / 3)."
    Write-Host "  Skips files if a valid merged output already exists."
    Write-Host "  Outputs condensed ffmpeg progress for each merge."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\merge-mp4-m4a.ps1 -Directory 'C:\Videos'"
    Write-Host "  .\merge-mp4-m4a.ps1 -Directory ''  # Uses current directory"
    exit
}

# If Directory is empty, use current directory
if ([string]::IsNullOrEmpty($Directory)) {
    $Directory = Get-Location
}

# Detect number of physical cores and calculate max parallel jobs
$numCores = (Get-CimInstance -ClassName Win32_Processor).NumberOfCores
$maxJobs = [math]::Floor($numCores / 3)
Write-Host "Detected $numCores cores. Running up to $maxJobs parallel jobs."

function Test-VideoFile {
    param($path)
    if (!(Test-Path $path)) { return $false }
    try {
        # Use ffmpeg to validate the file by attempting to process it to null
        $null = & ffmpeg -i $path -f null - -hide_banner -loglevel error 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

try {
    # Get all .m4a and .mp4 files in the directory (ignore script and other files)
    $files = Get-ChildItem -Path $Directory -File | Where-Object { $_.Extension -in '.m4a', '.mp4' }

    # Group files by base name (without extension)
    $groups = $files | Group-Object -Property { $_.BaseName }

    $jobs = @()

    # Initialize counters
    $merged = 0
    $reMerged = 0
    $skippedExists = 0
    $skippedNoPair = 0

    foreach ($group in $groups) {
        $basename = $group.Name
        
        # Skip if this basename already contains "-merged" (to avoid re-processing merged files)
        if ($basename -like "*-merged") {
            continue
        }
        
        # Find the .m4a and .mp4 files for this basename
        $m4aFile = $group.Group | Where-Object { $_.Extension -eq '.m4a' }
        $mp4File = $group.Group | Where-Object { $_.Extension -eq '.mp4' }
        
        # If both files exist, check if merged file already exists and is valid
        if ($m4aFile -and $mp4File) {
            $outputPath = Join-Path $Directory "$basename-merged.mp4"
            
            if ((Test-Path $outputPath) -and (Test-VideoFile $outputPath)) {
                Write-Host "Merged file $basename-merged.mp4 already exists and is valid. Skipping."
                $skippedExists++
                continue
            } elseif (Test-Path $outputPath) {
                # Exists but invalid, so re-merging
                $reMerged++
            } else {
                $merged++
            }
            
            # ffmpeg command to merge video from .mp4 and audio from .m4a
            # -c:v copy: copy video stream without re-encoding
            # -c:a aac: encode audio to AAC (common for MP4)
            # -map 0:v:0: use video from first input (mp4)
            # -map 1:a:0: use audio from second input (m4a)
            $ffmpegCmd = "ffmpeg -i `"$($mp4File.FullName)`" -i `"$($m4aFile.FullName)`" -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 `"$outputPath`" -y -hide_banner -loglevel error"
            
            Write-Host "Starting merge job for $basename..."
            
            # Start the job in parallel
            $job = Start-Job -ScriptBlock {
                param($cmd)
                $output = Invoke-Expression $cmd 2>&1
                $exitCode = $LASTEXITCODE
                # Filter ffmpeg output to show only first 2 lines, "...", and last 2 lines
                $lines = $output -split "`n" | Where-Object { $_ -match '\S' }  # Remove empty lines
                if ($lines.Count -gt 4) {
                    $filtered = $lines[0..1] + "..." + $lines[-2..-1]
                    Write-Host ($filtered -join "`n")
                } elseif ($lines.Count -gt 0) {
                    Write-Host ($lines -join "`n")
                }
                $exitCode
            } -ArgumentList $ffmpegCmd
            
            $jobs += $job
            
            # Limit concurrent jobs
            $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
            if ($runningJobs.Count -ge $maxJobs) {
                Write-Host "Max jobs reached, waiting for one to complete..."
                $null = Wait-Job -Job $runningJobs -Any
            }
        } else {
            Write-Host "Warning: Missing pair for $basename (m4a: $($m4aFile -ne $null), mp4: $($mp4File -ne $null))"
            $skippedNoPair++
        }
    }

    # Wait for all jobs to complete
    Write-Host "Waiting for all merge jobs to complete..."
    $jobs | Wait-Job

    # Check results
    foreach ($job in $jobs) {
        $result = Receive-Job $job
        # For simplicity, just report
        if ($result -eq 0) {
            Write-Host "Successfully merged a file"
            $merged++
        } else {
            Write-Host "Error merging a file"
        }
        Remove-Job $job
    }

    Write-Host "Merging process completed."

    # Summary
    $total = $merged + $reMerged + $skippedExists + $skippedNoPair
    Write-Host "Summary:"
    Write-Host "  Merged: $merged"
    Write-Host "  Re-Merged: $reMerged (from a bad previous merge)"
    Write-Host "  Skipped - Merge exists: $skippedExists"
    Write-Host "  Skipped - No matching pairs: $skippedNoPair"
    Write-Host "  Total: $total"
} finally {
    # Ensure all jobs are stopped and cleaned up if script is interrupted
    if ($jobs) {
        Write-Host "Stopping any running jobs..."
        $jobs | Where-Object { $_.State -eq 'Running' } | Stop-Job
        $jobs | Remove-Job -ErrorAction SilentlyContinue
    }
}