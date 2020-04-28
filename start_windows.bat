set ScriptDir=%~dp0
mkdir "%APPDATA%\TerminusDB"
mkdir "%APPDATA%\TerminusDB\tmp"
set TERMINUS_SERVER_DB_PATH=%APPDATA%\TerminusDB\db
set TERMINUS_SERVER_REGISTRY_PATH=%APPDATA%\TerminusDB\registry.pl
set TERMINUS_SERVER_TMP_PATH=%APPDATA%\TerminusDB\tmp
set TERMINUS_SERVER_INDEX_PATH=%APPDATA%\TerminusDB\index.html
set TERMINUS_LOG_PATH=%APPDATA%\TerminusDB\httpd.log
if not exist %TERMINUS_SERVER_DB_PATH% "%ScriptDir%swipl\bin\swipl" utils\db_util -s localhost -k root --autologin=true
"%ScriptDir%swipl\bin\swipl.exe" start.pl