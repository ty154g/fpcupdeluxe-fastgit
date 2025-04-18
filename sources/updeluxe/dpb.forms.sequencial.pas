unit DPB.Forms.Sequencial;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  ValEdit
  {$IFDEF USEMORMOT}
  , mormot.core.buffers
  {$IFDEF UNIX}
  , mormot.lib.openssl11
  {$ENDIF UNIX}
  {$ELSE}
  {$IF FPC_FULLVERSION < 30200}
  , ssockets
  , sslsockets
  {$ENDIF}
  {$ENDIF}
  ;

type

  { TDownload }
  TDownload = record
    URL: String;
    Filename: String;
  end;

  { TfrmSequencial }

  TfrmSequencial = class(TForm)
    CheckBox1: TCheckBox;
    CheckBox2: TCheckBox;
    lblTop: TLabel;
    lblDownloads: TLabel;
    lblBytes: TLabel;
    lblTop1: TLabel;
    pbDownloads: TProgressBar;
    pbBytes: TProgressBar;
    ValueListEditor1: TValueListEditor;
    procedure CheckBox1Change(Sender: TObject);
    procedure FormCreate({%H-}Sender: TObject);
    procedure FormActivate({%H-}Sender: TObject);
  private
    FDownloads: Array of TDownload;
    FSize: Int64;
    FSuccess: boolean;
    {$IFDEF USEMORMOT}
        procedure DataReceived(Sender: TStreamRedirect);
    {$ELSE}
    {$IF FPC_FULLVERSION < 30200}
        procedure GetSocketHandler(Sender: TObject; const UseSSL: Boolean;
          out AHandler: TSocketHandler);
    {$ENDIF}
        procedure DataReceived({%H-}Sender : TObject; const {%H-}ContentLength, CurrentPos : Int64);
    {$ENDIF}
    procedure DoDownload(const AIndex: Integer);
  public
    procedure AddDownload(const AURL, AFilename: String);
    property Success:boolean read FSuccess;
  end;

var
  frmSequencial: TfrmSequencial;

implementation

uses
  FileCtrl, FileUtil, inifiles,
  {$IFDEF USEMORMOT}
    mormot.net.client
  {$ELSE}
    fphttpclient
  {$IF FPC_FULLVERSION >= 30200}
    , opensslsockets
  {$ELSE}
    , fpopenssl
    , openssl
  {$ENDIF}
  {$ENDIF}
  //, DPB.Common.Utils
  ;

{$R *.lfm}


function FormatBytes(ABytes: Int64): String;

  function FormatReal(ASize: Double): String;
  begin
    Result:= EmptyStr;
    if ASize < 10 then
    begin
      Result:= FormatFloat('0.00', ASize);
      exit;
    end;
    if ASize < 100 then
    begin
      Result:= FormatFloat('00.0', ASize);
      exit;
    end;
    if ASize < 1000 then
    begin
      Result:= FormatFloat('#000', ASize);
      exit;
    end;
    if ASize < 1024 then
    begin
      Result:= FormatFloat('0000', ASize);
      exit;
    end;
  end;

var
  dSize: Double = 0.0;
begin
  Result := '';
  if ABytes < 1024 then
  begin
    Result:= ' B';
    exit;
  end;
  if ABytes < (1024*1024) then
  begin
    dSize:= ABytes / 1024;
    Result:= FormatReal(dSize) + ' KB';
    exit;
  end;
  if ABytes < (1024*1024*1024) then
  begin
    dSize:= ABytes / 1024 / 1024;
    Result:= FormatReal(dSize) + ' MB';
    exit;
  end;
  if ABytes < (1024*1024*1024*1024) then
  begin
    dSize:= ABytes / 1024 / 1024 / 1024;
    Result:= FormatReal(dSize) + 'GB';
    exit;
  end;
  if ABytes < (1024*1024*1024*1024*1024) then
  begin
    dSize:= ABytes / 1024 / 1024 / 1024 / 1024;
    Result:= FormatReal(dSize) + ' TB';
  end;
end;


{ TfrmSequencial }

procedure TfrmSequencial.FormCreate(Sender: TObject);
begin
  FSize:=0;
  FSuccess:=true;
  CheckBox1Change(nil);
  ValueListEditor1.ColWidths[0] := 200;
end;

procedure TfrmSequencial.FormActivate(Sender: TObject);
var
  fIni: TIniFile;
  strs: TStrings;
  str,s: String;
  index: Integer;
begin
  OnActivate:=nil;
  lblDownloads.Visible:=(Length(FDownloads)>1);
  pbDownloads.Visible:=lblDownloads.Visible;
  Application.ProcessMessages;
  if pbDownloads.Visible then pbDownloads.Max:= Length(FDownloads);
  index:=0;
  fIni := TIniFile.Create(ChangeFileExt(Application.Params[0], '.pro.ini'));
  strs := TStringList.Create;
  if not fIni.SectionExists('LIST') then begin
    fIni.WriteBool('BACK','Enabled', True);
    fIni.WriteString('LIST', 'https://github.com/', 'https://github.proxy.class3.fun/https://github.com/');
  end;
  fIni.ReadSection('LIST', strs);
  repeat
    str := strs.Strings[index];
    ValueListEditor1.Values[str] := fIni.ReadString('LIST', str, str);
    Inc(index);
  until index>=strs.Count;
  CheckBox2.Checked := fIni.ReadBool('BACK','Enabled', True);
  fIni.Free;
  strs.Free;
  s := ExtractFilePath(Application.Params[0]);
  s := s + 'tmp-bak' + s[Length(s)];
  ForceDirectories(s);
  index:=0;
  if Length(FDownloads)>0 then repeat
    //ValueListEditor1.Tag:=0;
    // Adjust text width and text length to be exactly the same width as the progress bar.
    lblTop.Caption:= Format('File: %s',[MiniMizeName(FDownloads[index].Filename, lblTop.Canvas, pbBytes.Width)]);
    //lblTop.Caption:= Format('File: %s',[FDownloads[index].Filename]);
    if lblDownloads.Visible then lblDownloads.Caption:= Format('%d of %d', [index + 1, Length(FDownloads)]);
    Application.ProcessMessages;
    try
      DoDownload(index);
    except
      on E: Exception do
      begin
        FSuccess:=false;
        break;
      end;
    end;
    if CheckBox2.Checked then
      CopyFile(FDownloads[index].Filename, s+ExtractFileName(FDownloads[index].Filename));
    Inc(index);
    if pbDownloads.Visible then
    begin
      pbDownloads.Position:= index;
      Application.ProcessMessages;
    end;
  until (index=Length(FDownloads));
  if FSuccess then FSuccess:=(index=Length(FDownloads));
  lblTop.Caption := 'The works has finished!';
  if Length(FDownloads)>0 then Close;
end;

procedure TfrmSequencial.CheckBox1Change(Sender: TObject);
begin
  if CheckBox1.Checked then Height := 380 else Height := 200;
end;

{$IFNDEF USEMORMOT}
{$IF FPC_FULLVERSION < 30200}
procedure TfrmSequencial.GetSocketHandler(Sender: TObject;
  const UseSSL: Boolean; out AHandler: TSocketHandler);
begin
  AHandler := TSSLSocketHandler.Create;
  TSSLSocketHandler(AHandler).SSLType := stTLSv1_2;
end;
{$ENDIF}
{$ENDIF}

procedure TfrmSequencial.DoDownload(const AIndex: Integer);
var
{$IFDEF USEMORMOT}
  params: THttpClientSocketWGet;
{$ELSE}
  http: TFPHTTPClient;
  k, index: Integer;
{$ENDIF}
  s, t, r : String;
begin
  {$IFNDEF USEMORMOT}
  {$IF FPC_FULLVERSION < 30200}
    InitSSLInterface;
  {$ENDIF}
    http:= TFPHTTPClient.Create(nil);
  {$IF FPC_FULLVERSION < 30200}
    http.OnGetSocketHandler:=@GetSocketHandler;
  {$ENDIF}
    http.AllowRedirect:= True;
  {$ENDIF}
  pbBytes.Position:= 0;
  CheckBox1.Checked:=False;
  t := ExtractFilePath(FDownloads[AIndex].Filename);
  r := t + 'tmp-bak' + t[Length(t)] + ExtractFileName(FDownloads[AIndex].Filename);
  if FileExists(r) then begin
    CopyFile(r, FDownloads[AIndex].Filename);
	end else try
    s := FDownloads[AIndex].URL;
    //try
    //  {$IFDEF USEMORMOT}
    //  params.Clear;
    //  params.Resume := true;
    //  params.OnProgress := @DataReceived;
    //  if params.WGet(s, FDownloads[AIndex].Filename,
    //       '', nil, 5000, 5) <> FDownloads[AIndex].Filename then
    //  begin
    //  end;
    //  {$ELSE}
    //  lblBytes.Caption:= 'Determining size...';
    //  Application.ProcessMessages;
    //  http.HTTPMethod('HEAD', s, nil, []);
    //  //TFPHTTPClient.Head(s, headers);
    //  FSize := 0;
    //  for index := 0 to Pred(http.ResponseHeaders.Count) do
    //  begin
    //    if LowerCase(http.ResponseHeaders.Names[index]) = 'content-length' then
    //    begin
    //      FSize:= StrToInt64(http.ResponseHeaders.ValueFromIndex[index]);
    //    end;
    //  end;
    //  http.OnDataReceived:= @DataReceived;
    //  http.Get(s, FDownloads[AIndex].Filename);
    //  {$ENDIF}
    //except
    //  on E: Exception do
    //  begin
    //    FSuccess:=false;
    //  end;
    //end;
    //if FSuccess=false then
    try
      CheckBox1.Checked:=True;
      index := 0;
      repeat
        t := ValueListEditor1.Keys[index];
        k := Length(t);
        r := Copy(s,1,k);
        if t=r then begin
          r := ValueListEditor1.Values[t];
          s := r + Copy(s,k+1,Length(s));
          Break;
        end;
        Inc(index);
      until index>ValueListEditor1.Strings.Count;

      {$IFDEF USEMORMOT}
      params.Clear;
      params.Resume := true;
      params.OnProgress := @DataReceived;
      if params.WGet(s, FDownloads[AIndex].Filename,
           '', nil, 5000, 5) <> FDownloads[AIndex].Filename then
      begin
      end;
      {$ELSE}
      lblBytes.Caption:= 'Determining size...';
      Application.ProcessMessages;

      http.HTTPMethod('HEAD', s, nil, []);
      //TFPHTTPClient.Head(s, headers);
      FSize := 0;
      for index := 0 to Pred(http.ResponseHeaders.Count) do
      begin
        if LowerCase(http.ResponseHeaders.Names[index]) = 'content-length' then
        begin
          FSize:= StrToInt64(http.ResponseHeaders.ValueFromIndex[index]);
        end;
      end;
      http.OnDataReceived:= @DataReceived;
      http.Get(s, FDownloads[AIndex].Filename);
      {$ENDIF}
    except
      on E: Exception do
      begin
        FSuccess:=false;
      end;
    end;
  finally
    {$IFNDEF USEMORMOT}
    http.Free;
    {$ENDIF}
  end;
end;

procedure TfrmSequencial.AddDownload(const AURL, AFilename: String);
var
  len: Integer;
begin
  { #todo 1 -ogcarreno : Maybe test for duplicates? }
  len:= Length(FDownloads);
  SetLength(FDownloads, len + 1);
  FDownloads[len].URL:= AURL;
  FDownloads[len].Filename:= AFilename;
end;

{$IFDEF USEMORMOT}
procedure TfrmSequencial.DataReceived(Sender: TStreamRedirect);
var
  aStream:TStreamRedirect;
begin
  aStream:=TStreamRedirect(Sender);
  pbBytes.Position:= aStream.Percent;
  lblBytes.Caption:= Format('%s of %s', [FormatBytes(aStream.ProcessedSize), FormatBytes(aStream.ExpectedSize)]);
  Application.ProcessMessages;
end;
{$ELSE}
procedure TfrmSequencial.DataReceived(Sender: TObject; const ContentLength, CurrentPos: Int64);
var
  currentPercent: Double;
begin
  if FSize>0 then currentPercent:= (CurrentPos*100)/FSize;
  pbBytes.Position:= round(currentPercent);
  lblBytes.Caption:= Format('%s of %s', [FormatBytes(CurrentPos), FormatBytes(FSize)]);
  Application.ProcessMessages;
end;
{$ENDIF}

end.

