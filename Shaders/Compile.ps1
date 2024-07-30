$null = New-Item -Path $PSScriptRoot -Name "compiled" -ItemType "directory" -Force
$shaders = Get-ChildItem "$PSScriptRoot/*" -Include "*.vert", "*.frag"



foreach ($shader in $shaders)
{
    $command = "glslc $PSScriptRoot/"
    $command += $shader.Name
    $command += " -o $PSScriptRoot/compiled/"
    $command += $shader.Name
    $command += ".spv"
    Invoke-Expression $command
}