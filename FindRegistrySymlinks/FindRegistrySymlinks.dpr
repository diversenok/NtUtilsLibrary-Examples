program FindRegistrySymlinks;

{
  This program demonstrates:
   - Working with the registry
   - Basic errror handling
   - Using iterating functions
}

{$APPTYPE CONSOLE}
{$R *.res}

uses
  Ntapi.ntdef, DelphiApi.Reflection, Ntapi.ntregapi, NtUtils, NtUtils.Registry,
  NtUtils.SysUtils, NtUiLib.Console;

type
  TOnFoundSymlink =  reference to procedure (const Name, Target: String);

function FindSymlinks(
  OnFoundSymlink: TOnFoundSymlink;
  Name: String;
  [opt] const RootName: String = '';
  [opt] ObjectAttributes: IObjectAttributes = nil
): TNtxStatus;
var
  hxKey: IHandle;
  Flags: TKeyFlagsInformation;
  SubKey: TNtxRegKey;
  SymlinkTarget: String;
begin
  // Open the key without following symlinks
  Result := NtxOpenKey(hxKey, Name, KEY_ENUMERATE_SUB_KEYS or KEY_QUERY_VALUE,
    0, AttributeBuilder(ObjectAttributes).UseAttributes(OBJ_OPENLINK));

  if not Result.IsSuccess then
    Exit;

  if RootName <> '' then
    Name := RtlxCombinePaths(RootName, Name);

  // Query flags to determine if the key is a symlink
  Result := NtxKey.Query(hxKey.Handle, KeyFlagsInformation, Flags);

  if not Result.IsSuccess then
    Exit;

  if BitTest(Flags.KeyFlags and REG_FLAG_LINK) then
  begin
    // It is a symlink; query the target
    Result := NtxQueryValueKeyString(hxKey.Handle, REG_SYMLINK_VALUE_NAME,
      SymlinkTarget);

    if Result.IsSuccess then
      OnFoundSymlink(Name, SymlinkTarget);
  end
  else
  begin
    // It's not a symlink; iterate sub-keys recursively
    for SubKey in NtxIterateKeys(@Result, hxKey) do
      FindSymlinks(OnFoundSymlink, SubKey.Name, Name,
        AttributeBuilder(ObjectAttributes).UseRoot(hxKey));
  end;
end;

begin
  writeln('Scanning HKLM for symlinks, it might take a while...');

  FindSymlinks(
    procedure(const Name, Target: String)
    begin
      writeln(Name, ' -> ', Target);
    end,
    REG_PATH_MACHINE
  );

  writeln('Completed.');
end.
