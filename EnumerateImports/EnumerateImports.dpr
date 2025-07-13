program EnumerateImports;

{
  This program demonstrates:
   - Parsing PE file imports
   - Using pretty error reporting
}

{$APPTYPE CONSOLE}
{$R *.res}

uses
  Ntapi.ntpebteb, NtUtils, NtUtils.Files, NtUtils.Files.Open, NtUtils.Sections,
  NtUtils.ImageHlp, NtUtils.SysUtils, NtUiLib.Console, NtUiLib.Errors;

function Main: TNtxStatus;
var
  FileName: String;
  MappedMemory: IMemory;
  Imports: TArray<TImportDllEntry>;
  Import: TImportDllEntry;
  FunctionEntry: TImportEntry;
  Count: Integer;
begin
  FileName := RtlxParamStr(1);

  if FileName = '' then
  begin
    writeln('You can pass the filename as a parameter; using the current executable...');
    writeln;
    FileName := RtlGetCurrentPeb.ProcessParameters.ImagePathName.ToString;
  end;

  // Open the file, create a section, and map it into the our process
  Result := RtlxMapFileByName(
    FileParameters.UseFileName(FileName, fnWin32),
    NtxCurrentProcess,
    MappedMemory,
    MappingParameters.UseProtection(PAGE_READONLY),
    SEC_COMMIT
  );

  if not Result.IsSuccess then
    Exit;

  // Parse the PE structure and find normal & delayed imports
  Result := RtlxEnumerateImportImage(Imports, MappedMemory.Region, False,
    [itNormal, itDelayed]);

  if not Result.IsSuccess then
    Exit;

  Count := 0;

  // Print them
  for Import in Imports do
  begin
    writeln(Import.DllName);

    for FunctionEntry in Import.Functions do
    begin
      if FunctionEntry.ImportByName then
        write('  ', FunctionEntry.Name)
      else
        write('  #', FunctionEntry.Ordinal);

      if FunctionEntry.DelayedImport then
        writeln(' (delayed)')
      else
        writeln;

      Inc(Count);
    end;
  end;

  writeln;
  writeln('Found ', Count, ' imports.');
end;

procedure ReportFailures(const Status: TNtxStatus);
begin
  // Use the constant name such as STATUS_ACCESS_DENIED when available
  if not Status.IsSuccess then
    writeln(Status.ToString, #$D#$A#$D#$A, RtlxNtStatusMessage(Status.Status));
end;

begin
  ReportFailures(Main);
end.
