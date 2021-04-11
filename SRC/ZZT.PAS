{
	Copyright (c) 2020 Adrian Siekierka

	Based on a reconstruction of code from ZZT,
	Copyright 1991 Epic MegaGames, used with permission.

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
}

{$I-}
{$IFNDEF FPC}
{$IFDEF NEC98}
{$M 24576,163840,655360}
{$ELSE}
{$M 20480,163840,655360}
{$ENDIF}
{$ENDIF}
program ZZT;
uses 
{$IFDEF NEC98}
Pc98,
{$ELSE}
Crt,
{$ENDIF}
Dos, ExtMem, ZVideo, Keys, Sounds, Input, TxtWind, GameVars, Elements, Editor, Oop, Game;

procedure ParseArguments;
	var
		i: integer;
		pArg: string;
		enableEms: boolean;
		enableXms: boolean;
	begin
		enableEms := true;
		enableXms := true;

		for i := 1 to ParamCount do begin
			pArg := ParamStr(i);
			if pArg[1] = '/' then begin
				case UpCase(pArg[2]) of
					'R': ResetConfig := true;
				end;

				if pArg = '/NOEMS' then
					enableEms := false
				else if pArg = '/NOXMS' then
					enableXms := false;
			end else begin
				StartupWorldFileName := pArg;
				if (Length(StartupWorldFileName) > 4) and (StartupWorldFileName[Length(StartupWorldFileName) - 3] = '.') then begin
					StartupWorldFileName := Copy(StartupWorldFileName, 1, Length(StartupWorldFileName) - 4);
				end;
			end;
		end;

		ExtMemInstall(enableEms, enableXms);
	end;

{$IFNDEF NEC98}
procedure WritelnCentered(s: string);
	var
		y: byte;
	begin
		y := WhereY;
		GotoXY(1 + ((80 - Length(s)) shr 1), y);
		Writeln(s);
	end;
{$ENDIF}

procedure GameConfigure;
	var
		unk1: integer;
		joystickEnabled, mouseEnabled: boolean;
		cfgFile: text;
	begin
		ParsingConfigFile := true;
		EditorEnabled := true;
{$IFDEF CONFREGI}
		ConfigRegistration := '';
{$ENDIF}
		ConfigWorldFile := '';
		GameVersion := '%VERSION%';

		Assign(cfgFile, 'zzt.cfg');
		Reset(cfgFile);
		if IOResult = 0 then begin
			Readln(cfgFile, ConfigWorldFile);
{$IFDEF CONFREGI}
			Readln(cfgFile, ConfigRegistration);
{$ENDIF}
			Close(cfgFile);
		end;

		if ConfigWorldFile[1] = '*' then begin
			EditorEnabled := false;
			ConfigWorldFile := Copy(ConfigWorldFile, 2, Length(ConfigWorldFile) - 1);
		end;
		if Length(ConfigWorldFile) <> 0 then begin
			StartupWorldFileName := ConfigWorldFile;
		end;

		InputInitDevices;
		joystickEnabled := InputJoystickEnabled;
		mouseEnabled := InputMouseEnabled;

		ParsingConfigFile := false;

{$IFNDEF NEC98}
		Window(1, 1, 80, 25);
		TextBackground(Black);
		ClrScr;
		TextColor(White);
		TextColor(White);
		Writeln;
		WritelnCentered('<=-  %NAME%  -=>');
		TextColor(Yellow);
		WritelnCentered('Version %VERSION%');
		WritelnCentered('%CONFIG_SUBTITLE%');
		GotoXY(1, 7);
		TextColor(Blue);
		Write('================================================================================');
		GotoXY(1, 24);
		Write('================================================================================');
		TextColor(White);
		GotoXY(30, 7);
		Write(' Game Configuration ');
		GotoXY(1, 25);
		Write(' %COPYRIGHT% ');
		GotoXY(59, 25);
		Write(' Press ... to abort ');
		TextColor(Black);
		TextBackground(LightGray);
		GotoXY(66, 25);
		Write('ESC');
		Window(1, 8, 80, 23);
		TextColor(Yellow);
		TextBackground(Black);
		ClrScr;
		TextColor(Yellow);
{$ENDIF}
		if not InputConfigure then
			GameTitleExitRequested := true
		else begin
{$IFNDEF NEC98}
			TextColor(LightGreen);
{$ENDIF}
			if not VideoConfigure then
				GameTitleExitRequested := true;
		end;
{$IFNDEF NEC98}
		Window(1, 1, 80, 25);
{$ENDIF}
	end;

begin
{$IFDEF WORLDDSC}
	WorldFileDescCount := 7;
	WorldFileDescKeys[1] := 'TOWN';
	WorldFileDescValues[1] := 'TOWN       The Town of ZZT';
	WorldFileDescKeys[2] := 'DEMO';
	WorldFileDescValues[2] := 'DEMO       Demo of the ZZT World Editor';
	WorldFileDescKeys[3] := 'CAVES';
	WorldFileDescValues[3] := 'CAVES      The Caves of ZZT';
	WorldFileDescKeys[4] := 'DUNGEONS';
	WorldFileDescValues[4] := 'DUNGEONS   The Dungeons of ZZT';
	WorldFileDescKeys[5] := 'CITY';
	WorldFileDescValues[5] := 'CITY       Underground City of ZZT';
	WorldFileDescKeys[6] := 'BEST';
	WorldFileDescValues[6] := 'BEST       The Best of ZZT';
	WorldFileDescKeys[7] := 'TOUR';
	WorldFileDescValues[7] := 'TOUR       Guided Tour ZZT'#39's Other Worlds';
{$ENDIF}

	Randomize;
{$IFNDEF NEC98}
	SetCBreak(false);
	InitialTextAttr := TextAttr;
{$ENDIF}

	StartupWorldFileName := 'TOWN';
{$IFDEF SUBDIRS}
	ResourceDataFileName := FExpand('ZZT.DAT');
{$ELSE}
	ResourceDataFileName := 'ZZT.DAT';
{$ENDIF}
	ResetConfig := false;
	GameTitleExitRequested := false;
	IoTmpBufSize := IO_BUFFER_DEFAULT_SIZE;
	GameConfigure;
	ParseArguments;

	if not GameTitleExitRequested then begin
		VideoInstall(Blue);
		{ OrderPrintId := @GameVersion; }
		TextWindowInit; { (5, 3, 50, 18) }
		GetMem(IoTmpBuf, IoTmpBufSize);

		VideoHideCursor;
		ClrScr;

		TickSpeed := 4;
		DebugEnabled := false;
{$IFDEF EXTCHEAT}
		CheatNoClip := false;
		CheatFreeze := false;
{$ENDIF}
{$IFDEF DEBUGWND}
		DebugCompatEnabled := false;
{$ENDIF}
		SavedGameFileName := 'SAVED';
		SavedBoardFileName := 'TEMP';
		ResetCachedLinePos;
		WorldCreate;

		GameTitleLoop;

		FreeMem(IoTmpBuf, IoTmpBufSize);
		ExtMemUninstall;
	end;

	SoundUninstall;
	SoundClearQueue;

	VideoUninstall;
{$IFNDEF NEC98}
	TextAttr := InitialTextAttr;
{$ENDIF}
	ClrScr;

	VideoShowCursor;
end.
