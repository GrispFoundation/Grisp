program OpenAIFirefoxProxyServer;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
	Unit_OpenAIProxy in 'Unit_OpenAIProxy.pas',
	Unit_OpenAIServer in 'Unit_OpenAIServer.pas',
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

begin
	Randomize;

	try
		Writeln;
		Writeln('OpenAI Firefox Proxy');
		Writeln('====================');
		Writeln;

		Writeln(
			'Firefox automation server:'
		);

		Writeln(
			'  TCP localhost:' +
			IntToStr(FIREFOX_PORT)
		);

		Writeln;

		vRestServer :=
			TOpenAIRestServer.Create(
				FIREFOX_PORT
			);

		try
			vHttpServer :=
				TRestHttpServer.Create(
					[
						vRestServer
					],
					RawUtf8(
						IntToStr(HTTP_PORT)
					)
				);

			try
				// CORS is useful if browser-based applications access
				// the local OpenAI-compatible server.
				vHttpServer.AccessControlAllowOrigin :=
					'*';

				Writeln(
					'HTTP server listening on:'
				);

				Writeln(
					'  http://127.0.0.1:' +
					IntToStr(HTTP_PORT)
				);

				Writeln;
				Writeln('Important mORMot internal root: /api');
				Writeln;

				Writeln(
					'Native mORMot endpoint:'
				);

				Writeln(
					'  POST /api/V1ChatCompletions'
				);

				Writeln;

				Writeln(
					'Models endpoint:'
				);

				Writeln(
					'  GET /api/V1Models'
				);

				Writeln;

				Writeln(
					'Press ENTER to stop.'
				);

				ReadLn;

			finally
				vHttpServer.Free;
			end;

		finally
			vRestServer.Free;
		end;

	except
		on E: Exception do
		begin
			Writeln;
			Writeln(
				'Fatal error: ' +
				E.ClassName
			);

			Writeln(
				E.Message
			);

			ReadLn;

			ExitCode := 1;
		end;
	end;
end.
