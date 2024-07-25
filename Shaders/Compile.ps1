$null = New-Item -Path "./" -Name "compiled" -ItemType "directory" -Force
$shaders = Get-ChildItem "./*" -Include "*.vert", "*.frag"



foreach ($shader in $shaders)
{
    $command = "glslc ./"
    $command += $shader.Name
    $command += " -o ./compiled/"
    $command += $shader.Name
    $command += ".spv"
    Invoke-Expression $command
}