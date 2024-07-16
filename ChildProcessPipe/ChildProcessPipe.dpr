program ChildProcessPipe;

{
  This program demonstrates:
   - Creating processes
   - Creating anonymous pipes
   - Using pipes for I/O redirection
}

{$APPTYPE CONSOLE}
{$R *.res}

uses
  Ntapi.WinNt, Ntapi.ntdef, Ntapi.ntioapi, Ntapi.ntioapi.fsctl, Ntapi.ntpebteb,
  Ntapi.ntstatus, Ntapi.WinUser, NtUtils, NtUtils.Files.Operations,
  NtUtils.Files.Open, NtUtils.Processes.Create, NtUtils.Processes.Create.Win32,
  NtUiLib.Console, NtUiLib.Errors;

// This function is analogous to kernel32's CreatePipe
function NtxCreateAnonymousPipes(
  out hxReadPipe: IHandle;
  out hxWritePipe: IHandle;
  ReadPipeFlags: TObjectAttributesFlags = 0;
  WritePipeFlags: TObjectAttributesFlags = 0
): TNtxStatus;
var
  hxNamedPipeRoot: IHandle;
begin
  // Open the named pipe device root
  Result := NtxOpenFile(hxNamedPipeRoot, FileParameters
    .UseFileName(DEVICE_NAMED_PIPE)
  );

  if not Result.IsSuccess then
    Exit;

  // Create an unnamed pipe (for reading)
  Result := NtxCreatePipe(hxReadPipe, FileParameters
    .UseRoot(hxNamedPipeRoot)
    .UseDisposition(FILE_CREATE)
    .UseAccess(FILE_WRITE_ATTRIBUTES or GENERIC_READ)
    .UseHandleAttributes(ReadPipeFlags)
    .UsePipeType(FILE_PIPE_BYTE_STREAM_TYPE)
    .UsePipeReadMode(FILE_PIPE_BYTE_STREAM_MODE)
    .UsePipeCompletion(FILE_PIPE_QUEUE_OPERATION)
    .UsePipeMaximumInstances(1)
  );

  if not Result.IsSuccess then
    Exit;

  // Reopen the pipe (for writing)
  Result := NtxOpenFile(hxWritePipe, FileParameters
    .UseRoot(hxReadPipe)
    .UseAccess(FILE_READ_ATTRIBUTES or GENERIC_WRITE)
    .UseHandleAttributes(WritePipeFlags)
  );
end;

function Main: TNtxStatus;
const
  BUFFER_SIZE = 64;
var
  hxOutRead, hxInWrite: IHandle;
  Options: TCreateProcessOptions;
  Info: TProcessInfo;
  Buffer: array [0 .. BUFFER_SIZE - 1] of AnsiChar;
  BufferString: AnsiString;
  BytesRead: NativeUInt;
begin
  Options := Default(TCreateProcessOptions);
  Options.Flags := [poUseStdHandles, poInheritConsole, poInheritHandles,
    poUseWindowMode];
  Options.WindowMode := TShowMode32.SW_HIDE;
  Options.Application := USER_SHARED_DATA.NtSystemRoot + '\system32\cmd.exe';
  Options.Parameters := '/c "whoami"';

  // Create a pipe for reading program's output
  Result := NtxCreateAnonymousPipes(hxOutRead, Options.hxStdOutput, 0, OBJ_INHERIT);

  if not Result.IsSuccess then
    Exit;

  // Create a pipe for writing program's input
  Result := NtxCreateAnonymousPipes(Options.hxStdInput, hxInWrite, OBJ_INHERIT, 0);

  if not Result.IsSuccess then
    Exit;

  // Share regular and error output
  Options.hxStdError := Options.hxStdOutput;

  // Spawn the process
  Result := AdvxCreateProcess(Options, Info);

  if not Result.IsSuccess then
    Exit;

  // Close our copies of pipe handles meant for the child process to know when
  // it disconnects
  Options.hxStdInput := nil;
  Options.hxStdOutput := nil;
  Options.hxStdError := nil;

  repeat
    // Read a portion of program's output
    Result := NtxReadFile(hxOutRead.Handle, @Buffer, SizeOf(Buffer), 0, nil,
      @BytesRead);

    // Gracefully exit on disconnect
    if Result.Status = STATUS_PIPE_BROKEN then
    begin
      Result := NtxSuccess;
      Break;
    end;

    if not Result.IsSuccess then
      Break;

    // Save and truncate the output
    SetString(BufferString, Buffer, BytesRead);

    // Report it
    writeln('Received ', BytesRead, ' bytes: ', BufferString);
  until not Result.IsSuccess;
end;

procedure RunMain;
var
  Status: TNtxStatus;
begin
  Status := Main;

  if Status.IsSuccess then
    writeln('Success.')
  else
    writeln(Status.ToString);
end;

begin
  RunMain;
end.
