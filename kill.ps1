# START -wait "wmic" "process where name=""TCPSVCS.EXE call"" terminate"""
# START -wait -WindowStyle Hidden "taskkill.exe" "/f /fi ""IMAGENAME eq TCPSVCS.EXE"" /fi ""STATUS eq NOT RESPONDING"""

 
   if ( $allProcesses = get-process -name TCPSVCS -errorAction SilentlyContinue ) {
         foreach ($oneProcess in $allProcesses) {
                      $oneProcess.kill()
             } 
         }
