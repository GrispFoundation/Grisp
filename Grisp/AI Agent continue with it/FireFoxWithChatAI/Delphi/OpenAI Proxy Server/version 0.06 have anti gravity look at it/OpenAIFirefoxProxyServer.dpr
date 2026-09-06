program OpenAIFirefoxProxyServer;

{

OpenAI FireFox (<-with AI Automation modification) Proxy Server

version 0.01 to 0.05 created on 3 september 2026 by Skybuck Flying and Deepseek, ChatGPT and especially Co-Pilot.

status: version 0.04 and 0.05 working !

version 0.05 has better shutdown code, no more exceptions.


These versions were written against/using the repository:

https://github.com/synopse/mORMot2

* commit aef05e96dcd947c2dd0a82818c47a449f2ba99bd (HEAD -> master, origin/master, origin/HEAD)
| Author: Arnaud Bouchez <ab@synopse.info>
| Date:   Tue Sep 1 18:57:22 2026 +0200
|
|     net: some Tunnel logic fixes
|     - especially for less used methods

}

(*

OpenAI Firefox Proxy Server - Reference and Debugging Notes
---------------------------------------------------------

Purpose
  The OpenAI Firefox Proxy Server accepts OpenAI-style chat completion requests
  and translates them into browser automation commands for a controlled Firefox
  automation agent. It is intended for testing and running agentic workflows
  that drive a browser (open pages, click, fill, read text) and return results
  in an OpenAI-compatible JSON format.

Capabilities
  - Accepts OpenAI-style chat completion requests (model + messages) and maps
    model names to target sites (deepseek-chat -> deepseek, chatgpt -> chatgpt, etc.).
  - Builds a "prompt" command for the Firefox automation agent that includes:
      * command: "prompt"
      * site: mapped site name
      * text: the last non-empty user message
      * tab: tab index (reused if cached or discovered)
  - Queries the Firefox automation agent (TCP) and converts its JSON reply into
    an OpenAI-style response (choices, usage, error translation).
  - Returns structured error JSON for communication or automation failures:
      * firefox_comm_error (communication problems)
      * firefox_automation_error (automation returned an error)
      * invalid_request_error (bad client request)
  - Runtime debug control: enable/disable logging, change debug level, change log file.
  - Safe shutdown pattern: proxy exposes Shutdown to terminate workers before freeing
    resources; ownership flag prevents double-free of shared logger.

HTTP Endpoints (base: http://127.0.0.1:8080)
  GET  /api/V1Models
      - Returns a JSON list of supported models and their site mapping.
  POST /api/V1ChatCompletions
      - Main entry point. Accepts OpenAI-style JSON:
        { "model":"deepseek-chat", "messages":[{"role":"user","content":"..."}] }
      - Returns OpenAI-style chat completion JSON or structured error JSON.
  GET  /api/V1Debug
      - Read-only debug status:
        { "enabled": <bool>, "level": <int>, "logfile": "<path>" }

Default ports and files
  - HTTP server: 127.0.0.1:8080
  - Firefox automation agent (TCP): 127.0.0.1:9999 (configurable at proxy creation)
  - Default log file: openai_proxy.log (next to the EXE unless overridden)

Quick usage examples (Windows cmd.exe)
  Single-line curl (escape quotes):
    curl -s -X POST "http://127.0.0.1:8080/api/V1ChatCompletions" -H "Content-Type: application/json" -d "{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello from curl test\"}]}"
  Using a file (recommended to avoid escaping issues):
    1) Create request.json (UTF-8 without BOM):
       {"model":"deepseek-chat","messages":[{"role":"user","content":"Hello from file"}]}
    2) Send:
       curl -s -X POST "http://127.0.0.1:8080/api/V1ChatCompletions" -H "Content-Type: application/json" --data-binary @request.json
  PowerShell (recommended on Windows):
    $body = @{ model="deepseek-chat"; messages=@(@{ role="user"; content="Hello from PowerShell test" }) } | ConvertTo-Json
    Invoke-RestMethod -Uri "http://127.0.0.1:8080/api/V1ChatCompletions" -Method Post -ContentType "application/json" -Body $body
  Extract assistant text with jq (Unix or Windows with jq installed):
    curl -s ... | jq -r '.choices[0].message.content'

Common troubleshooting
  - "Request body is empty" (400)
      * The server received no body. On Windows ensure the curl command is a single line
        or use caret ^ for continuation in cmd.exe. Prefer PowerShell or --data-binary @file.
  - "Invalid JSON request body"
      * The server received bytes it could not parse as JSON. Common causes:
        - Incorrect escaping in cmd.exe curl (use file or PowerShell).
        - UTF-8 BOM at start of body. Save request file without BOM or strip BOM.
        - Trailing backslash or stray characters in the command line.
      * Debug: save the request to a file and send with --data-binary @file; validate JSON locally.
  - "Firefox automation server returned an empty response"
      * The Firefox automation agent did not reply. Check the agent is running and reachable
        on the configured port (default 9999). Check firewall rules.
  - "firefox_automation_error"
      * The automation agent returned an error object (e.g., sign-in required, missing selector).
        Inspect the returned error.message for details and ensure the controlled Firefox profile
        is signed in and the expected page structure is present.

Debugging support and variables
  - Log file:
      * Default: openai_proxy.log (next to EXE)
      * Can be changed at startup via OpenAISettings.LogFile or at runtime via SetLogFile.
  - Debug enable/level:
      * DebugEnabled: boolean (true/false)
      * DebugLevel: integer mapping:
          0 = off
          1 = error
          2 = info
          3 = verbose
      * Methods:
          - TOpenAIProxy.SetDebugEnabled(Boolean)
          - TOpenAIProxy.SetDebugLevel(Integer)
          - TOpenAIProxy.SetLogFile(String)
      * Endpoint:
          - GET /api/V1Debug returns enabled, level, logfile
  - Runtime logging:
      * The proxy logs incoming requests, built Firefox commands, replies from Firefox,
        and errors. Use Get-Content (PowerShell) or tail -f to follow the log:
          PowerShell: Get-Content .\openai_proxy.log -Wait -Tail 50
  - Shutdown and destructor safety:
      * Call TOpenAIProxy.Shutdown to terminate worker threads and wait for them before freeing.
      * The proxy uses an ownership flag (FOwnsLogger) so the logger is only freed by the owner.
      * Use FreeAndNil on top-level objects in the correct order:
          1) Stop HTTP server (free TRestHttpServer)
          2) Free REST server (TOpenAIRestServer) which calls proxy.Shutdown in its destructor
          3) Ensure logger is freed only once (server or proxy depending on ownership)
  - Memory and crash diagnostics:
      * Enable FastMM full debug in the Delphi project to detect double frees and memory corruption.
      * Use MadExcept or EurekaLog to capture full exception stacks on crashes (destructor-time crashes).
  - Temporary diagnostic logging to add (examples)
      * Add mLogger.Log(dlVerbose, 'TOpenAIProxy.Shutdown start'); at the start of Shutdown.
      * Add mLogger.Log(dlVerbose, 'TOpenAIProxy.Destroy start'); at the start of Destroy.
      * Add mLogger.Log(dlVerbose, Format('InBody length=%d first32=%s', [Length(Ctxt.Call.InBody), BinToHex(Copy(Ctxt.Call.InBody,1,32))])); in V1ChatCompletions to inspect raw bytes.

Best practices
  - Use PowerShell or file-based requests on Windows to avoid escaping and BOM issues.
  - Keep the controlled Firefox profile signed in for long test runs; re-auth flows break automation.
  - Rotate logs for long-running servers and monitor disk usage.
  - Use unique test tokens in prompts (e.g., TESTID-<timestamp>) to correlate requests with proxy/firefox logs.
  - Add small delays and retries in client harnesses for transient errors (exponential backoff).
  - When adding background threads that use the logger or critical sections, always Terminate + WaitFor
    the threads before freeing synchronization objects.

Notes about automation protocol
  - The proxy sends JSON commands to the Firefox automation agent over TCP. Typical command:
      {"command":"prompt","site":"deepseek","text":"...","tab":-1}
  - The agent replies with JSON containing either "text" or "error". The proxy converts that into
    an OpenAI-style response or an error object.

Contact and next steps
  - If you need a test harness, a PowerShell script to run multi-turn tests, or a small patch to add
    more diagnostic logging, add the request JSON and I will provide the script or patch.

*)


{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Unit_OpenAIProxy in 'Unit_OpenAIProxy.pas',
  Unit_OpenAIServer in 'Unit_OpenAIServer.pas',
  Unit_OpenAISettings in 'Unit_OpenAISettings.pas',
  mormot.core.base in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.base.pas',
  mormot.core.buffers in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.buffers.pas',
  mormot.core.collections in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.collections.pas',
  mormot.core.data in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.data.pas',
  mormot.core.datetime in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.datetime.pas',
  mormot.core.fmt in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.fmt.pas',
  mormot.core.fpclibcmm in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.fpclibcmm.pas',
  mormot.core.fpcx64mm in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.fpcx64mm.pas',
  mormot.core.i18n in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.i18n.pas',
  mormot.core.interfaces in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.interfaces.pas',
  mormot.core.json in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.json.pas',
  mormot.core.log in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.log.pas',
  mormot.core.mustache in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.mustache.pas',
  mormot.core.mvc in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.mvc.pas',
  mormot.core.os.delphi in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.os.delphi.pas',
  mormot.core.os.mac in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.os.mac.pas',
  mormot.core.os in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.os.pas',
  mormot.core.os.security in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.os.security.pas',
  mormot.core.perf in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.perf.pas',
  mormot.core.rtti in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.rtti.pas',
  mormot.core.search in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.search.pas',
  mormot.core.test in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.test.pas',
  mormot.core.text in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.text.pas',
  mormot.core.threads in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.threads.pas',
  mormot.core.unicode in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.unicode.pas',
  mormot.core.variants in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.variants.pas',
  mormot.core.zip in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\core\mormot.core.zip.pas',
  mormot.crypt.core in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.core.pas',
  mormot.crypt.ecc in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.ecc.pas',
  mormot.crypt.ecc256r1 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.ecc256r1.pas',
  mormot.crypt.jwt in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.jwt.pas',
  mormot.crypt.openssl in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.openssl.pas',
  mormot.crypt.other in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.other.pas',
  mormot.crypt.pkcs11 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.pkcs11.pas',
  mormot.crypt.rsa in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.rsa.pas',
  mormot.crypt.secure in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.secure.pas',
  mormot.crypt.x509 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\crypt\mormot.crypt.x509.pas',
  mormot.lib.curl in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.curl.pas',
  mormot.lib.gdiplus in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.gdiplus.pas',
  mormot.lib.gssapi in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.gssapi.pas',
  mormot.lib.lizard in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.lizard.pas',
  mormot.lib.openssl11 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.openssl11.pas',
  mormot.lib.pkcs11 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.pkcs11.pas',
  mormot.lib.quickjs in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.quickjs.pas',
  mormot.lib.sspi in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.sspi.pas',
  mormot.lib.static in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.static.pas',
  mormot.lib.uniscribe in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.uniscribe.pas',
  mormot.lib.win7zip in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.win7zip.pas',
  mormot.lib.winhttp in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.winhttp.pas',
  mormot.lib.z in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\lib\mormot.lib.z.pas',
  mormot.orm.base in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.base.pas',
  mormot.orm.client in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.client.pas',
  mormot.orm.core in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.core.pas',
  mormot.orm.mongodb in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.mongodb.pas',
  mormot.orm.rest in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.rest.pas',
  mormot.orm.server in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.server.pas',
  mormot.orm.sql in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.sql.pas',
  mormot.orm.sqlite3 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.sqlite3.pas',
  mormot.orm.storage in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\orm\mormot.orm.storage.pas',
  mormot.db.core in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.core.pas',
  mormot.db.nosql.bson in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.nosql.bson.pas',
  mormot.db.nosql.mongodb in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.nosql.mongodb.pas',
  mormot.db.proxy in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.proxy.pas',
  mormot.db.raw.odbc in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.raw.odbc.pas',
  mormot.db.raw.oledb in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.raw.oledb.pas',
  mormot.db.raw.oracle in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.raw.oracle.pas',
  mormot.db.raw.postgres in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.raw.postgres.pas',
  mormot.db.raw.sqlite3 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.raw.sqlite3.pas',
  mormot.db.raw.sqlite3.static in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.raw.sqlite3.static.pas',
  mormot.db.sql.odbc in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.sql.odbc.pas',
  mormot.db.sql.oledb in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.sql.oledb.pas',
  mormot.db.sql.oracle in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.sql.oracle.pas',
  mormot.db.sql in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.sql.pas',
  mormot.db.sql.postgres in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.sql.postgres.pas',
  mormot.db.sql.sqlite3 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\db\mormot.db.sql.sqlite3.pas',
  mormot.rest.client in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\rest\mormot.rest.client.pas',
  mormot.rest.core in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\rest\mormot.rest.core.pas',
  mormot.rest.http.client in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\rest\mormot.rest.http.client.pas',
  mormot.rest.http.server in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\rest\mormot.rest.http.server.pas',
  mormot.rest.memserver in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\rest\mormot.rest.memserver.pas',
  mormot.rest.mvc in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\rest\mormot.rest.mvc.pas',
  mormot.rest.server in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\rest\mormot.rest.server.pas',
  mormot.rest.sqlite3 in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\rest\mormot.rest.sqlite3.pas',
  mormot.net.acme in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.acme.pas',
  mormot.net.async in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.async.pas',
  mormot.net.client in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.client.pas',
  mormot.net.dhcp in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.dhcp.pas',
  mormot.net.dns in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.dns.pas',
  mormot.net.http in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.http.pas',
  mormot.net.ldap in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.ldap.pas',
  mormot.net.openapi in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.openapi.pas',
  mormot.net.relay in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.relay.pas',
  mormot.net.rtsphttp in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.rtsphttp.pas',
  mormot.net.server in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.server.pas',
  mormot.net.sock in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.sock.pas',
  mormot.net.tftp.client in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.tftp.client.pas',
  mormot.net.tftp.server in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.tftp.server.pas',
  mormot.net.tunnel in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.tunnel.pas',
  mormot.net.ws.async in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.ws.async.pas',
  mormot.net.ws.client in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.ws.client.pas',
  mormot.net.ws.core in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.ws.core.pas',
  mormot.net.ws.server in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\net\mormot.net.ws.server.pas',
  mormot.soa.client in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\soa\mormot.soa.client.pas',
  mormot.soa.codegen in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\soa\mormot.soa.codegen.pas',
  mormot.soa.core in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\soa\mormot.soa.core.pas',
  mormot.soa.server in 'K:\Delphi\Libraries\mORMot2\github 1 september 2026\src\soa\mormot.soa.server.pas';

const
  HTTP_PORT = 8080;
  FIREFOX_PORT = 9999;

var
  vRestServer: TOpenAIRestServer;
  vHttpServer: TRestHttpServer;
  StartupLogFile: string;

begin
  Randomize;
  vRestServer := nil;
  vHttpServer := nil;
  try
    Writeln;
    Writeln('OpenAI Firefox Proxy');
    Writeln('====================');
    Writeln;

    // default logfile next to exe if not set in OpenAISettings
    StartupLogFile := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'openai_proxy.log';
    if Unit_OpenAISettings.LogFile = '' then
       Unit_OpenAISettings.LogFile := StartupLogFile;

    // Create server using the settings variables
    vRestServer := TOpenAIRestServer.Create(
      FIREFOX_PORT,
      Unit_OpenAISettings.DebugEnabled,
      Unit_OpenAISettings.DebugLevel,
      Unit_OpenAISettings.LogFile
    );

    vHttpServer := TRestHttpServer.Create([vRestServer], RawUtf8(IntToStr(HTTP_PORT)));
    try
      vHttpServer.AccessControlAllowOrigin := '*';

      Writeln('HTTP server listening on:');
      Writeln('  http://127.0.0.1:' + IntToStr(HTTP_PORT));
      Writeln;
      Writeln('Important mORMot internal root: /api');
      Writeln;
      Writeln('Native mORMot endpoint:');
      Writeln('  POST /api/V1ChatCompletions');
      Writeln;
      Writeln('Models endpoint:');
      Writeln('  GET /api/V1Models');
      Writeln;
      Writeln('Debug status (read-only):');
      Writeln('  GET /api/V1Debug');
      Writeln;
      Writeln('Press ENTER to stop.');
      ReadLn;
    finally
      // Free HTTP server first (no Stop call because TRestHttpServer.Stop is not available)
      FreeAndNil(vHttpServer);
    end;

  finally
    // Free REST server (which will call proxy shutdown in its destructor)
    FreeAndNil(vRestServer);
  end;
end.


