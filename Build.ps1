$libs = Get-ChildItem -Path "./libs" -Exclude "*.lib"

foreach ($lib in $libs)
{
    Copy-Item -Path $lib.FullName -Destination ("./bin/" + $lib.Name)
}

$command = If ($args -match "-ex") {"OdinEx "} Else {"odin "}

$command += If ($args -match "-r") {"run "} Else {"build "}

$command += "./ "

$command += If ($args -match "-d") {"-debug "} Else {""}
$command += "-out:./bin/Program.exe"

Invoke-Expression $command