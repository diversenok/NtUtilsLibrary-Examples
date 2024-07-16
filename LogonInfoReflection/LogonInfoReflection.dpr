program LogonInfoReflection;

{
  This program demonstrates:
   - Querying token and logon information
   - Use of RTTI/reflection for type formatting
}

{$APPTYPE CONSOLE}
{$R *.res}

uses
  Ntapi.ntseapi, NtUtils, NtUtils.Tokens, NtUtils.Tokens.Info,
  NtUtils.Lsa.Logon, NtUtils.SysUtils, NtUiLib.Errors, NtUiLib.Console,
  DelphiUiLib.Reflection.Records, NtUiLib.Reflection.Types;

function QueryCurrentLogonSession(out Logon: ILogonSession): TNtxStatus;
var
  Statistics: TTokenStatistics;
begin
  // Query the current token's logon session ID
  Result := NtxToken.Query(NtxCurrentProcessToken, TokenStatistics, Statistics);

  if not Result.IsSuccess then
    Exit;

  // Lookup logon information
  Result := LsaxQueryLogonSession(Statistics.AuthenticationId, Logon);
end;

procedure Main;
var
  Status: TNtxStatus;
  LogonInfo: ILogonSession;
begin
  // Get logon details
  Status := QueryCurrentLogonSession(LogonInfo);

  if not Status.IsSuccess then
  begin
    writeln('Unable to query logon info: ', Status.ToString);
    Exit;
  end;

  // Use RTTI to pretty-print the SECURITY_LOGON_SESSION_DATA buffer we got
  TRecord.Traverse(LogonInfo.Data,
    procedure (const Field: TFieldReflection)
    const
      NAME_COLUMN_WIDTH = 38;
    var
      Padding: String;
    begin
      // Prepare the padding between columns
      if Length(Field.FieldName) < NAME_COLUMN_WIDTH then
        Padding := RtlxBuildString(' ', NAME_COLUMN_WIDTH -
          Length(Field.FieldName))
      else
        Padding := '';

      // Print the table
      writeln(Field.FieldName, Padding, ' | ',
        RtlxStringOrDefault(Field.Reflection.Text, '(none)'));
    end
  );
end;

begin
  Main;
end.
