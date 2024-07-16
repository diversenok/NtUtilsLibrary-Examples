program ShowProcessTree;

{
  This program demonstrates:
   - Enumerating processes on the system
   - Useing TArray helper for tree creation
}

{$APPTYPE CONSOLE}
{$R *.res}

uses
  NtUtils, NtUtils.SysUtils, NtUtils.Processes.Snapshots, NtUiLib.Console,
  DelphiUtils.Arrays;

procedure PrintSubTree(
  const Node: TTreeNode<TProcessEntry>;
  Depth: Integer = 0
);
var
  Child: ^TTreeNode<TProcessEntry>;
begin
  // Output the image name with a padding that indicates hierarchy
  writeln(RtlxBuildString(' ', Depth), Node.Entry.ImageName,
    ' [', Node.Entry.Basic.ProcessID, ']');

  // Show children recursively
  for Child in Node.Children do
    PrintSubTree(Child^, Depth + 2);
end;

procedure Main;
var
  Processes: TArray<TProcessEntry>;
  Tree: TArray<TTreeNode<TProcessEntry>>;
  Node: TTreeNode<TProcessEntry>;
begin
  // Ask the library to snapshot processes
  if not NtxEnumerateProcesses(Processes).IsSuccess then
    Exit;

  // Find all parent-child relationships between entries and build a tree using
  // the built-in parent checker
  Tree := TArray.BuildTree<TProcessEntry>(Processes, ParentProcessChecker);

  // Show each process with no parent as a tree root, then use recursion
  for Node in Tree do
    if not Assigned(Node.Parent) then
      PrintSubTree(Node);
end;

begin
  Main;
end.
