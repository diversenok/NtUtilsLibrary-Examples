program RunAsHighIL;

{
  This program demonstrates:
   - Use of the credential dialog
   - Performing logon
   - Performing various token manipulation
   - Process creation
   - Working with ACLs and security descriptors
   - Use of auto-reverters

  The demo is based on the following technique idea:
  https://x.com/splinter_code/status/1458054161472307204
}

{$R *.res}

uses
  Ntapi.WinNt,
  Ntapi.ntseapi,
  Ntapi.NtSecApi,
  Ntapi.ntpebteb,
  Ntapi.ProcessThreadsApi,
  Ntapi.WinError,
  Ntapi.WinUser,
  Ntapi.wincred,
  NtUtils,
  NtUtils.Tokens,
  NtUtils.Tokens.Info,
  NtUtils.Tokens.Logon,
  NtUtils.Tokens.Impersonate,
  NtUtils.Security,
  NtUtils.Security.Acl,
  NtUtils.Objects,
  NtUtils.Threads,
  NtUtils.Processes,
  NtUtils.Processes.Create,
  NtUtils.Processes.Create.Win32,
  NtUtils.WinUser,
  NtUiLib.WinCred,
  NtUtils.Errors,
  NtUiLib.Errors.Dialog;

function RtlxGrantTemporaryAccess(
  out AccessReverter: IAutoReleasable;
  const hxObject: IHandle;
  const Sid: ISid;
  AccessMask: TAccessMask
): TNtxStatus;
var
  OriginalDacl, NewDacl: IAcl;
begin
  // Query the current DACL
  Result := RtlxQueryDaclObject(hxObject, NtxQuerySecurityObject, OriginalDacl);

  if not Result.IsSuccess then
    Exit;

  // Make a copy of the DACL to modify
  Result := RtlxCopyAcl(NewDacl, OriginalDacl);

  if not Result.IsSuccess then
    Exit;

  // Add an access allowed ACE
  Result := RtlxAddAce(NewDacl, TAceData.New(ACCESS_ALLOWED_ACE_TYPE, 0,
    AccessMask, Sid));

  if not Result.IsSuccess then
    Exit;

  // Apply the new DACL
  Result := RtlxSetDaclObject(hxObject, NtxSetSecurityObject, NewDacl);

  if not Result.IsSuccess then
    Exit;

  AccessReverter := Auto.Delay(
    procedure
    begin
      // Restore the original DACL later
      RtlxSetDaclObject(hxObject, NtxSetSecurityObject, OriginalDacl);
    end
  );
end;

function Main: TNtxStatus;
const
  MSG_CAPTION = 'RunAsHighIL';
  MSG_TEXT = '';
var
  Options: TCreateProcessOptions;
  Info: TProcessInfo;
  Credentials: TLogonCredentials;
  Logon: TLogonInfo;
  LogonSid: TGroup;
  OurIntegeriy, TokenIntegrity: TIntegrityRid;
  ImpersonationReverter, ProcessDaclReverter: IAutoReleasable;
  WinStaDaclReverter, DesktopDaclReverter: IAutoReleasable;
begin
  // Ask for credentials on the secure desktop frist
  Result := CredxPromptForWindowsCredentials(0, MSG_CAPTION, MSG_TEXT,
    Credentials, CREDUIWIN_SECURE_PROMPT);

  // Retry on the regular desktop, in case the user cannot use the secure one
  if Result.Win32Error = ERROR_CANCELLED then
    Result := CredxPromptForWindowsCredentials(0, MSG_CAPTION, MSG_TEXT,
      Credentials);

  if not Result.IsSuccess then
  begin
    // Exit gracefully on cancellation
    if Result.Win32Error = ERROR_CANCELLED then
      Result := NtxSuccess;

    Exit;
  end;

  // Perform a network logon that avoids UAC filtration
  Result := LsaxLogonUser(Logon, TLogonSubmitType.InteractiveLogon,
    TSecurityLogonType.Network, Credentials, TTokenSource.New);

  if not Result.IsSuccess then
    Exit;

  // Determine our integrity
  Result := NtxQueryIntegrityToken(NtxCurrentProcessToken, OurIntegeriy);

  if not Result.IsSuccess then
    Exit;

  // Detemine the new token's integrity
  Result := NtxQueryIntegrityToken(Logon.hxToken, TokenIntegrity);

  if not Result.IsSuccess then
    Exit;

  if OurIntegeriy < TokenIntegrity then
  begin
    // Lower the token's integrity to match ours to allow impersonation
    Result := NtxSetIntegrityToken(Logon.hxToken, OurIntegeriy);

    if not Result.IsSuccess then
      Exit;
  end;

  // Impersonate the token and check for impersonation level downgrade
  Result := NtxSafeSetThreadToken(NtxCurrentThread, Logon.hxToken);

  if not Result.IsSuccess then
    Exit;

  ImpersonationReverter := Auto.Delay(
    procedure
    begin
      // Reset impersonation later
      NtxSetThreadToken(NtCurrentThread, nil);
    end
  );

  // Determine the logon SID of the token
  Result := NtxQueryLogonSidToken(Logon.hxToken, LogonSid);

  if not Result.IsSuccess then
    Exit;

  // Grant the token's logon SID access to our process so seclogon can open us
  Result := RtlxGrantTemporaryAccess(ProcessDaclReverter, NtxCurrentProcess,
    LogonSid.Sid, PROCESS_DUP_HANDLE or PROCESS_CREATE_PROCESS or
    PROCESS_QUERY_INFORMATION);

  if not Result.IsSuccess then
    Exit;

  // Grant accss to the current window station
  Result := RtlxGrantTemporaryAccess(WinStaDaclReverter,
    Auto.RefHandle(UsrxCurrentWindowStation), LogonSid.Sid, WINSTA_ALL_ACCESS);

  if not Result.IsSuccess then
    Exit;

  // Grant accss to the current desktop
  Result := RtlxGrantTemporaryAccess(DesktopDaclReverter,
    Auto.RefHandle(UsrxCurrentDesktop), LogonSid.Sid, DESKTOP_ALL_ACCESS);

  if not Result.IsSuccess then
    Exit;

  // Prepare for process creation
  Options := Default(TCreateProcessOptions);
  Options.Application := USER_SHARED_DATA.NtSystemRoot + '\system32\cmd.exe';
  Options.Flags := [poSuspended];
  Options.LogonFlags := LOGON_WITH_PROFILE or LOGON_NETCREDENTIALS_ONLY;
  Options.Domain := Credentials.Domain;
  Options.Username := Credentials.Username;
  Options.Password := Credentials.Password;

  // Ask seclogon to create the process
  Result := AdvxCreateProcessWithLogon(Options, Info);

  if not Result.IsSuccess then
    Exit;

  // Restore our process's DACL and reset impersonation
  ProcessDaclReverter := nil;
  ImpersonationReverter := nil;

  // Don't restore DACLs on window station and desktop (the process needs them)
  WinStaDaclReverter.AutoRelease := False;
  DesktopDaclReverter.AutoRelease := False;

  // Continue
  Result := NtxResumeThread(Info.hxThread.Handle);
end;

procedure RunMain;
var
  Status: TNtxStatus;
begin
  Status := Main;

  // Report the errors via UI
  if not Status.IsSuccess then
    ShowNtxStatus(0, Status);
end;

begin
  RunMain;
end.
