/*
	Combine multiple PerfMon files into One
*/
$sqlDiagOutputFolder = 'H:\Performance-Issues\Data-Collections\TUL1MDPDWMSH2C1\output_MAY_02';
$perfmonFiles = Get-ChildItem $sqlDiagOutputFolder | Where-Object {$_.Extension -eq '.BLG' };
$perfmonFiles | Select-Object -ExpandProperty FullName;

$blgFile1 = "H:\Performance-Issues\Data-Collections\TUL1MDPDWMSH2C1\output_MAY_02\SQLDIAG.BLG"
$blgFile2 = "H:\Performance-Issues\Data-Collections\TUL1MDPDWMSH2C1\output_MAY_02\SQLDIAG1.BLG"
$blgFile3 = "H:\Performance-Issues\Data-Collections\TUL1MDPDWMSH2C1\output_MAY_02\SQLDIAG2.BLG"
$blgFile4 = "H:\Performance-Issues\Data-Collections\TUL1MDPDWMSH2C1\output_MAY_02\SQLDIAG3.BLG"

$combinedFile = "H:\Performance-Issues\Data-Collections\TUL1MDPDWMSH2C1\output_MAY_02\SQLDIAG_Combined.BLG"

$AllArgs =  @($blgFile1,$blgFile2,$blgFile3,$blgFile4,  '-f', 'bin', '-o',  $combinedFile)

& 'relog.exe' $AllArgs