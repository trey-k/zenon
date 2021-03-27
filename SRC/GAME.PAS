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
{$V-}
unit Game;

interface
	uses GameVars, TxtWind;
	const
		PROMPT_NUMERIC = 0;
		PROMPT_ALPHANUM = 1;
		PROMPT_ANY = 2;
	procedure SidebarClearLine(y: integer);
	procedure SidebarClear;
	function EnsureIoTmpBufSize(size: integer): integer; { 1 if IoTmpBuf was wiped, 2 if the size is too large. }
	procedure AdvancePointer(var address: pointer; count: integer);
	procedure BoardClose;
	procedure BoardOpen(boardId: integer);
	procedure BoardChange(boardId: integer);
	procedure BoardCreate;
	procedure WorldCreate;
	procedure TransitionDrawToFill(chr: char; color: integer);
	procedure BoardDrawTile(x, y: integer);
	procedure BoardDrawBorder;
	procedure TransitionDrawToBoard;
	procedure SidebarPromptCharacter(editable: boolean; x, y: integer; prompt: TString50; var value: byte);
	procedure SidebarPromptSlider(editable: boolean; x, y: integer; prompt: string; var value: byte);
	procedure SidebarPromptChoice(editable: boolean; y: integer; prompt, choiceStr: string; var result: byte);
	procedure SidebarPromptDirection(editable: boolean; y: integer; prompt: string; var deltaX, deltaY: integer);
	procedure PromptString(x, y, arrowColor, color, width, stringLength: integer; mode: byte; var buffer: TString50);
	function SidebarPromptYesNo(message: string; defaultReturn: boolean): boolean;
	procedure SidebarPromptString(prompt: string; extension: TString50; var filename: string; promptMode: byte);
	procedure PauseOnError;
	function DisplayIOError: boolean;
	procedure WorldUnload;
	function WorldLoad(filename, extension: TString50; titleOnly: boolean): boolean;
	procedure WorldSave(filename, extension: TString50);
	procedure GameWorldSave(prompt: TString50; var filename: TString50; extension: TString50);
	function GameWorldLoad(extension: TString50): boolean;
	procedure CopyStatDataToTextWindow(statId: integer; var state: TTextWindowState);
	procedure AddStat(tx, ty: integer; element: byte; color, tcycle: integer; template: TStat);
	procedure FreeStatDataMem(statId: integer; showError: boolean);
	procedure RemoveStat(statId: integer);
	function GetStatIdAt(tx, ty: integer): integer;
	function BoardPrepareTileForPlacement(x, y: integer): boolean;
	procedure MoveStat(statId: integer; newX, newY: integer);
	procedure PopupPromptString(question: string; var buffer: TString50; maxLen: integer);
	function Signum(val: integer): integer;
	function Difference(a, b: integer): integer;
	procedure DamageStat(attackerStatId: integer);
	procedure BoardDamageTile(x, y: integer);
	procedure BoardAttack(attackerStatId: integer; x, y: integer);
	function BoardShoot(element: byte; tx, ty, deltaX, deltaY: integer; source: integer): boolean;
	procedure CalcDirectionRnd(var deltaX, deltaY: integer);
	procedure CalcDirectionSeek(x, y: integer; var deltaX, deltaY: integer);
	procedure TransitionDrawBoardChange;
	procedure GameUpdateSidebar;
	procedure GameAboutScreen;
	procedure GamePlayLoop(boardChanged: boolean);
	procedure DisplayMessage(time: integer; message: string);
	procedure BoardEnter;
	procedure BoardPassageTeleport(x, y: integer);
	procedure GameDebugPrompt;
	procedure GameTitleLoop;
const
	LFSR11_START = 42;
	ProgressAnimColors: array[0 .. 7] of byte = ($14, $1C, $15, $1D, $16, $1E, $17, $1F);
	ProgressAnimStrings: array[0 .. 7] of string[5] =
		('....|', '...*/', '..*.-', '.*..\', '*...|', '..../', '....-', '....\');
	ColorNames: array[1 .. 7] of string[8] =
		('Blue', 'Green', 'Cyan', 'Red', 'Purple', 'Yellow', 'White');
	{}
	DiagonalDeltaX: array[0 .. 7] of integer = (-1, 0, 1, 1, 1, 0, -1, -1);
	DiagonalDeltaY: array[0 .. 7] of integer = (1, 1, 1, 0, -1, -1, -1, 0);
	NeighborDeltaX: array[0 .. 3] of integer = (0, 0, -1, 1);
	NeighborDeltaY: array[0 .. 3] of integer = (-1, 1, 0, 0);
	{}
	TileBorder: TTile = (Element: E_NORMAL; Color: $0E);
	TileBoardEdge: TTile = (Element: E_BOARD_EDGE; Color: $00);
	StatTemplateDefault: TStat = (
		X: 0; Y: 0; StepX: 0; StepY: 0;
		Cycle: 0; P1: 0; P2: 0; P3: 0;
		Follower: -1; Leader: -1
	);
	LineChars: string[16] = #249#208#210#186#181#188#187#185#198#200#201#204#205#202#203#206;

implementation
uses
{$IFDEF DEBUGWND}
DebugWnd,
{$ENDIF}
Dos, Crt, FileSel, ExtMem, Video, Sounds, Input, Elements, Editor, Oop;

function LFSR11UpdateSeed(var seed: word; var tx, ty: byte): boolean;
	begin
		seed := (seed shr 1) xor ((-(seed and 1)) and $740);
		tx := (seed - 1) and $3F;
		ty := ((seed - 1) shr 6) and $3F;
		LFSR11UpdateSeed := seed = LFSR11_START;
	end;

procedure SidebarClearLine(y: integer);
	begin
		VideoWriteText(60, y, $11, #179'                   ');
	end;

procedure SidebarClear;
	var
		i: integer;

	begin
		for i := 3 to 24 do
			SidebarClearLine(i);
	end;

function EnsureIoTmpBufSize(size: integer): integer;
	var
		oldSize: integer;
	begin
		if size > IO_BUFFER_MAXIMUM_SIZE then begin
			EnsureIoTmpBufSize := 2;
			exit;
		end;
		oldSize := IoTmpBufSize;
		EnsureIoTmpBufSize := 0;
		while IoTmpBufSize < size do
			Inc(IoTmpBufSize, IO_BUFFER_SIZE_INCREMENT);
		if oldSize <> IoTmpBufSize then begin
			FreeMem(IoTmpBuf, oldSize);
			oldSize := IoTmpBufSize;
			IoTmpBufSize := 0;
			GetMem(IoTmpBuf, oldSize);
			EnsureIoTmpBufSize := 1;
		end;
	end;

procedure AdvancePointer(var address: pointer; count: integer);
	begin
		address := Ptr(Seg(address^), Ofs(address^) + count);
	end;

procedure BoardClose;
	var
		ix, iy: integer;
		ptr: pointer;
		rle: TRleTile;
	label RestartWrite;
	begin
		{ Bind stats early. }
		for ix := 0 to Board.StatCount do begin
			with Board.Stats[ix] do begin
				if DataLen > 0 then begin
					for iy := 1 to (ix - 1) do begin
						if Board.Stats[iy].Data = Data then
							DataLen := -iy;
					end;
				end;
			end;
		end;

	RestartWrite:
		ptr := IoTmpBuf;

		Move(Board.Name, ptr^, SizeOf(Board.Name));
		AdvancePointer(ptr, SizeOf(Board.Name));

		ix := 1;
		iy := 1;
		rle.Count := 1;
		rle.Tile := Board.Tiles[ix][iy];
		repeat
			Inc(ix);
			if ix > BOARD_WIDTH then begin
				ix := 1;
				Inc(iy);
			end;
			if (Board.Tiles[ix][iy].Color = rle.Tile.Color) and
				(Board.Tiles[ix][iy].Element = rle.Tile.Element) and
				(rle.Count < 255) and (iy <= BOARD_HEIGHT) then
			begin
				Inc(rle.Count);
			end else begin
				Move(rle, ptr^, SizeOf(rle));
				AdvancePointer(ptr, SizeOf(rle));
				rle.Tile := Board.Tiles[ix][iy];
				rle.Count := 1;
			end;
		until iy > BOARD_HEIGHT;

		Move(Board.Info, ptr^, SizeOf(Board.Info));
		AdvancePointer(ptr, SizeOf(Board.Info));

		Move(Board.StatCount, ptr^, SizeOf(Board.StatCount));
		AdvancePointer(ptr, SizeOf(Board.StatCount));

		{ We will always have enough size to store the above in the default IoTmpBuf. }
		{ From here, do size estimation. }
		iy := (Ofs(ptr^) - Ofs(IoTmpBuf^)) + ((Board.StatCount + 1) * SizeOf(TStat));

		for ix := 0 to Board.StatCount do begin
			with Board.Stats[ix] do begin
				if DataLen > 0 then
					Inc(iy, DataLen);
			end;
		end;

		case EnsureIoTmpBufSize(iy) of
			0: begin end; { We good. }
			1: goto RestartWrite; { Not so good. }
			2: RunError(203);
		end;

{$IFDEF DEBUGWND}
		if DebugCompatEnabled and (iy > IO_BUFFER_DEFAULT_SIZE) then
			DebugShowSizeTooLarge(IO_BUFFER_DEFAULT_SIZE, iy, World.Info.CurrentBoard,
				'Board', 'is above the ZZT 3.2 limit!');
{$ENDIF}

		for ix := 0 to Board.StatCount do begin
			with Board.Stats[ix] do begin
				Move(Board.Stats[ix], ptr^, SizeOf(TStat));
				AdvancePointer(ptr, SizeOf(TStat));
				if DataLen > 0 then begin
					Move(Data^, ptr^, DataLen);
					FreeMem(Data, DataLen);
					AdvancePointer(ptr, DataLen);
				end;
			end;
		end;

		ExtMemFree(World.BoardData[World.Info.CurrentBoard], World.BoardLen[World.Info.CurrentBoard]);
		World.BoardLen[World.Info.CurrentBoard] := Ofs(ptr^) - Ofs(IoTmpBuf^);
		if ExtMemGet(World.BoardData[World.Info.CurrentBoard], World.BoardLen[World.Info.CurrentBoard]) then begin
			ExtMemWrite(World.BoardData[World.Info.CurrentBoard], IoTmpBuf^, World.BoardLen[World.Info.CurrentBoard]);
		end else RunError(203);
	end;

procedure DebugBoardIllegalElements;
	var
		textWindow: TTextWindowState;
		xStr, yStr, zStr: string[11];
		count, ix, iy: integer;
	begin
		count := 0;
		for iy := 1 to BOARD_HEIGHT do
			for ix := 1 to BOARD_WIDTH do
				with Board.Tiles[ix][iy] do
					if (Element > MAX_ELEMENT) and (not
					(Element in [238, 239, 240, 241, 244, 246, 248, 250, 252, 254])) then begin
						if count = 0 then begin
							textWindow.Title := '[Debug] Illegal Elements';
							TextWindowInitState(textWindow);
							TextWindowAppend(textWindow, 'Illegal elements detected on board at:');
							TextWindowAppend(textWindow, '');
						end;
						Str(ix, xStr);
						Str(iy, yStr);
						Str(Element, zStr);
						TextWindowAppend(textWindow, xStr + ', ' + yStr + ': ID ' + zStr);
						Inc(count);
					end;
		if count > 0 then begin
			TextWindowDrawOpen(textWindow);
			TextWindowSelect(textWindow, false, false);
			TextWindowDrawClose(textWindow);
			TextWindowFree(textWindow);
		end;
	end;

procedure BoardOpen(boardId: integer);
	var
		ptr: pointer;
		ix, iy: integer;
		rle: TRleTile;
	begin
		if boardId > World.BoardCount then
			boardId := World.Info.CurrentBoard;

		case EnsureIoTmpBufSize(World.BoardLen[boardId]) of
			0, 1: begin end;
			2: RunError(203);
		end;

		ExtMemRead(World.BoardData[boardId], IoTmpBuf^, World.BoardLen[boardId]);

		ptr := IoTmpBuf;

		Move(ptr^, Board.Name, SizeOf(Board.Name));
		AdvancePointer(ptr, SizeOf(Board.Name));

		ix := 1;
		iy := 1;
		rle.Count := 0;
		repeat
			if rle.Count <= 0 then begin
				Move(ptr^, rle, SizeOf(rle));
				AdvancePointer(ptr, SizeOf(rle));
			end;
			Board.Tiles[ix][iy] := rle.Tile;
			Inc(ix);
			if ix > BOARD_WIDTH then begin
				ix := 1;
				Inc(iy);
			end;
			Dec(rle.Count);
		until iy > BOARD_HEIGHT;

		Move(ptr^, Board.Info, SizeOf(Board.Info));
		AdvancePointer(ptr, SizeOf(Board.Info));

		Move(ptr^, Board.StatCount, SizeOf(Board.StatCount));
		AdvancePointer(ptr, SizeOf(Board.StatCount));

		for ix := 0 to Board.StatCount do
			with Board.Stats[ix] do begin
				Move(ptr^, Board.Stats[ix], SizeOf(TStat));
				AdvancePointer(ptr, SizeOf(TStat));
				if DataLen > 0 then begin
					GetMem(Data, DataLen);
					Move(ptr^, Data^, DataLen);
					AdvancePointer(ptr, DataLen);
				end else if DataLen < 0 then begin
					Data := Board.Stats[-DataLen].Data;
					DataLen := Board.Stats[-DataLen].DataLen;
				end;
			end;

		World.Info.CurrentBoard := boardId;
	end;

procedure BoardChange(boardId: integer);
	begin
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_PLAYER;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[E_PLAYER].Color;
		BoardClose;
		BoardOpen(boardId);
	end;

procedure BoardCreate;
	var
		ix, iy, i: integer;
	begin
		Board.Name := '';
		Board.Info.Message := '';
		Board.Info.MaxShots := 255;
		Board.Info.IsDark := false;
		Board.Info.ReenterWhenZapped := false;
		Board.Info.TimeLimitSec := 0;
		for i := 0 to 3 do
			Board.Info.NeighborBoards[i] := 0;

		for ix := 0 to BOARD_WIDTH+1 do begin
			Board.Tiles[ix][0] := TileBoardEdge;
			Board.Tiles[ix][BOARD_HEIGHT+1] := TileBoardEdge;
		end;
		for iy := 0 to BOARD_HEIGHT+1 do begin
			Board.Tiles[0][iy] := TileBoardEdge;
			Board.Tiles[BOARD_WIDTH+1][iy] := TileBoardEdge;
		end;

		for ix := 1 to BOARD_WIDTH do
			for iy := 1 to BOARD_HEIGHT do begin
				Board.Tiles[ix][iy].Element := E_EMPTY;
				Board.Tiles[ix][iy].Color := 0;
			end;

		for ix := 1 to BOARD_WIDTH do begin
			Board.Tiles[ix][1] := TileBorder;
			Board.Tiles[ix][BOARD_HEIGHT] := TileBorder;
		end;
		for iy := 1 to BOARD_HEIGHT do begin
			Board.Tiles[1][iy] := TileBorder;
			Board.Tiles[BOARD_WIDTH][iy] := TileBorder;
		end;

		Board.Tiles[BOARD_WIDTH div 2][BOARD_HEIGHT div 2].Element := E_PLAYER;
		Board.Tiles[BOARD_WIDTH div 2][BOARD_HEIGHT div 2].Color := ElementDefs[E_PLAYER].Color;
		Board.StatCount := 0;
		Board.Stats[0].X := BOARD_WIDTH div 2;
		Board.Stats[0].Y := BOARD_HEIGHT div 2;
		Board.Stats[0].Cycle := 1;
		Board.Stats[0].Under.Element := E_EMPTY;
		Board.Stats[0].Under.Color := 0;
		Board.Stats[0].Data := nil;
		Board.Stats[0].DataLen := 0;
	end;

procedure WorldCreate;
	var
		i: integer;
	begin
		InitElementsGame;
		World.BoardCount := 0;
		World.BoardLen[0] := 0;
		InitEditorStatSettings;
		ResetMessageNotShownFlags;
		BoardCreate;
		World.Info.IsSave := false;
		World.Info.CurrentBoard := 0;
		World.Info.Ammo := 0;
		World.Info.Gems := 0;
		World.Info.Health := 100;
		World.Info.EnergizerTicks := 0;
		World.Info.Torches := 0;
		World.Info.TorchTicks := 0;
		World.Info.Score := 0;
		World.Info.BoardTimeSec := 0;
		World.Info.BoardTimeHsec := 0;
		for i := 1 to 7 do
			World.Info.Keys[i] := false;
		for i := 1 to MAX_FLAG do
			World.Info.Flags[i] := '';
		BoardChange(0);
		Board.Name := 'Title screen';
		LoadedGameFileName := '';
		World.Info.Name := '';
	end;

procedure TransitionDrawToFill(chr: char; color: integer);
	var
		seed: word;
		tx, ty: byte;
	begin
		seed := LFSR11_START;
		repeat
			if (tx < 60) and (ty < 25) then
				VideoWriteText(tx, ty, color, chr);
		until LFSR11UpdateSeed(seed, tx, ty);

		if (tx < 60) and (ty < 25) then
			VideoWriteText(tx, ty, color, chr);
	end;

procedure BoardDrawTile(x, y: integer);
	var
		ch: byte;
	begin
		with Board.Tiles[x][y] do begin
			if not Board.Info.IsDark
				or (ElementDefs[Element].VisibleInDark)
				or (
					(World.Info.TorchTicks > 0)
					and ((Sqr(Board.Stats[0].X - x) + Sqr(Board.Stats[0].Y - y) * 2) < TORCH_DIST_SQR)
				) or ForceDarknessOff then
			begin
				if Element = E_EMPTY then
					VideoWriteText(x - 1, y - 1, $0F, ' ')
				else if (Element <= MAX_ELEMENT) and ElementDefs[Element].HasDrawProc then begin
					ElementDefs[Element].DrawProc(x, y, ch);
{$IFDEF EXTCHEAT}
					VideoWriteText(x - 1, y - 1, Color xor CheatColorModifiers[Element], Chr(ch));
{$ELSE}
					VideoWriteText(x - 1, y - 1, Color, Chr(ch));
{$ENDIF}
				end else if Element < E_TEXT_MIN then
{$IFDEF EXTCHEAT}
					VideoWriteText(x - 1, y - 1, Color xor CheatColorModifiers[Element],
						ElementDefs[Element].Character)
{$ELSE}
					VideoWriteText(x - 1, y - 1, Color, ElementDefs[Element].Character)
{$ENDIF}
				else begin
					{ Text drawing }
					if Element = E_TEXT_WHITE then
						VideoWriteText(x - 1, y - 1, $0F, Chr(Color))
					else if VideoMonochrome then
						VideoWriteText(x - 1, y - 1, ((Element - E_TEXT_MIN) + 1) shl 4, Chr(Color))
					else
						VideoWriteText(x - 1, y - 1, (((Element - E_TEXT_MIN) + 1) shl 4) + $F, Chr(Color));
				end
			end else begin
				{ Darkness }
				VideoWriteText(x - 1, y - 1, $07, #176);
			end;
		end;
	end;

procedure BoardDrawBorder;
	var
		ix, iy: integer;
	begin
		for ix := 1 to BOARD_WIDTH do begin
			BoardDrawTile(ix, 1);
			BoardDrawTile(ix, BOARD_HEIGHT);
		end;

		for iy := 1 to BOARD_HEIGHT do begin
			BoardDrawTile(1, iy);
			BoardDrawTile(BOARD_WIDTH, iy);
		end;
	end;

procedure TransitionDrawToBoard;
	var
		seed: word;
		tx, ty: byte;
	begin
		BoardDrawBorder;

		seed := LFSR11_START;
		repeat
			if (tx < 60) and (ty < 25) then
				BoardDrawTile(tx+1, ty+1);
		until LFSR11UpdateSeed(seed, tx, ty);


		if (tx < 60) and (ty < 25) then
			BoardDrawTile(tx+1, ty+1);
	end;

procedure SidebarPromptCharacter(editable: boolean; x, y: integer; prompt: TString50; var value: byte);
	var
		i, newValue: integer;
	begin
		SidebarClearLine(y);
		VideoWriteText(x, y, Integer(editable) + $1E, prompt);
		SidebarClearLine(y + 1);
		VideoWriteText(x + 5, y + 1, $9F, #31);
		SidebarClearLine(y + 2);

		repeat
			for i := (value - 4) to (value + 4) do
				VideoWriteText(((x + i) - value) + 5, y + 2, $1E, Chr(i and $FF));

			if editable then begin
				Delay(25);
				InputUpdate;
				if (InputKeyPressed = KEY_TAB) or (InputKeyPressed = KEY_PAGE_DOWN) then
					InputDeltaX := 9
				else if (InputKeyPressed = KEY_PAGE_UP) then
					InputDeltaX := -9;

				newValue := value + InputDeltaX;
				if value <> newValue then begin
					value := newValue and $FF;
					SidebarClearLine(y + 2);
				end;
			end;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) or not editable or InputShiftPressed;

		VideoWriteText(x + 5, y + 1, $1F, #31);
	end;

procedure SidebarPromptSlider(editable: boolean; x, y: integer; prompt: string; var value: byte);
	var
		newValue: integer;
		startChar, endChar: char;
	begin
		if prompt[Length(prompt) - 2] = ';' then begin
			startChar := prompt[Length(prompt) - 1];
			endChar := prompt[Length(prompt)];
			prompt := Copy(prompt, 1, Length(prompt) - 3);
		end else begin
			startChar := '1';
			endChar := '9';
		end;

		SidebarClearLine(y);
		VideoWriteText(x, y, Integer(editable) + $1E, prompt);
		SidebarClearLine(y + 1);
		SidebarClearLine(y + 2);
		VideoWriteText(x, y + 2, $1e, startChar + '....:....' + endChar);

		repeat
			if editable then begin
				if InputJoystickMoved then
					Delay(45);
				VideoWriteText(x + value + 1, y + 1, $9F, #31);

				InputUpdate;
				if (InputKeyPressed >= '1') and (InputKeyPressed <= '9') then begin
					value := Ord(InputKeyPressed) - 49;
					SidebarClearLine(y + 1);
				end else begin
					if (InputKeyPressed = KEY_PAGE_DOWN) then
						newValue := 8
					else if (InputKeyPressed = KEY_PAGE_UP) then
						newValue := 0
					else
						newValue := value + InputDeltaX;
					if (value <> newValue) and (newValue >= 0) and (newValue <= 8) then begin
						value := newValue;
						SidebarClearLine(y + 1);
					end;
				end;
			end;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) or not editable or InputShiftPressed;

		VideoWriteText(x + value + 1, y + 1, $1F, #31);
	end;

procedure SidebarPromptChoice(editable: boolean; y: integer; prompt, choiceStr: string; var result: byte);
	var
		i, j, choiceCount: integer;
		newResult: integer;
	begin
		SidebarClearLine(y);
		SidebarClearLine(y + 1);
		SidebarClearLine(y + 2);
		VideoWriteText(63, y, Integer(editable) + $1E, prompt);
		VideoWriteText(63, y + 2, $1E, choiceStr);

		choiceCount := 1;
		for i := 1 to Length(choiceStr) do
			if choiceStr[i] = ' ' then
				Inc(choiceCount);

		repeat
			j := 0;
			i := 1;
			while (j < result) and (i < Length(choiceStr)) do begin
				if choiceStr[i] = ' ' then
					Inc(j);	
				Inc(i);
			end;

			if editable then begin
				VideoWriteText(62 + i, y + 1, $9F, #31);
				Delay(35);
				InputUpdate;

				if (InputKeyPressed = KEY_PAGE_DOWN) then
					newResult := choiceCount - 1
				else if (InputKeyPressed = KEY_PAGE_UP) then
					newResult := 0
				else
					newResult := result + InputDeltaX;
				if (result <> newResult) and (newResult >= 0) and (newResult <= (choiceCount - 1)) then begin
					result := newResult;
					SidebarClearLine(y + 1);
				end;
			end;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) or not editable or InputShiftPressed;

		VideoWriteText(62 + i, y + 1, $1F, #31);
	end;

procedure SidebarPromptDirection(editable: boolean; y: integer; prompt: string; var deltaX, deltaY: integer);
	var
		choice: byte;
	begin
		if deltaY = -1 then
			choice := 0
		else if deltaY = 1 then
			choice := 1
		else if deltaX = -1 then
			choice := 2
		else
			choice := 3;
		SidebarPromptChoice(editable, y, prompt, #24' '#25' '#27' '#26, choice);
		deltaX := NeighborDeltaX[choice];
		deltaY := NeighborDeltaY[choice];
	end;

procedure PromptString(x, y, arrowColor, color, width, stringLength: integer; mode: byte; var buffer: TString50);
	var
		i, iOffs: integer;
		oldBuffer: string;
		firstKeyPress: boolean;
	begin
		oldBuffer := buffer;
		firstKeyPress := true;

		repeat
			iOffs := Length(buffer) - width;
			if iOffs < 0 then iOffs := 0;
			for i := 0 to (width - 1) do begin
				VideoWriteText(x + i, y, color, ' ');
				VideoWriteText(x + i, y - 1, arrowColor, ' ');
			end;
			VideoWriteText(x + width, y - 1, arrowColor, ' ');
			VideoWriteText(x + Length(buffer) - iOffs, y - 1, (arrowColor and $F0) + $0F, #31);
			VideoWriteText(x, y, color, Copy(buffer, iOffs + 1, width));

			InputReadWaitKey;

			if (Length(buffer) < stringLength) and (InputKeyPressed >= #32) and (InputKeyPressed < #128) then begin
				if firstKeyPress then
					buffer := '';
				case mode of
					PROMPT_NUMERIC: begin
						if (InputKeyPressed in ['0' .. '9']) then begin
							buffer := buffer + InputKeyPressed;
						end;
					end;
					PROMPT_ANY: begin
						buffer := buffer + InputKeyPressed;
					end;
					PROMPT_ALPHANUM: begin
						if (UpCase(InputKeyPressed) in ['A' .. 'Z'])
							or (InputKeyPressed in ['0' .. '9'])
							or (InputKeyPressed = '-') then
						begin
							buffer := buffer + UpCase(InputKeyPressed);
						end;
					end;
				end;
			end else if (InputKeyPressed = KEY_LEFT) or (InputKeyPressed = KEY_BACKSPACE) then begin
				buffer := Copy(buffer, 1, Length(buffer) - 1);
			end;

			firstKeyPress := false;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE);
		if InputKeyPressed = KEY_ESCAPE then begin
			buffer := oldBuffer;
		end;
	end;

function SidebarPromptYesNo(message: string; defaultReturn: boolean): boolean;
	begin
		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);
		VideoWriteText(63, 5, $1F, message);
		VideoWriteText(63 + Length(message), 5, $9E, '_');

		repeat
			InputReadWaitKey;
		until UpCase(InputKeyPressed) in [KEY_ESCAPE, 'N', 'Y'];
		if UpCase(InputKeyPressed) = 'Y' then
			defaultReturn := true
		else
			defaultReturn := false;

		SidebarClearLine(5);
		SidebarPromptYesNo := defaultReturn;
	end;

procedure SidebarPromptString(prompt: string; extension: TString50; var filename: string; promptMode: byte);
	begin
		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);
		VideoWriteText(75 - Length(prompt), 3, $1F, prompt);
		VideoWriteText(63, 5, $0F, '        ' + extension);

		PromptString(63, 5, $1E, $0F, 8, 8, promptMode, filename);

		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);
	end;

procedure PauseOnError;
	begin
		SoundQueue(1, SoundParse('s004x114x9'));
		AccurateDelay(2000);
	end;

function DisplayIOError: boolean;
	var
		ioResValue: word;
		errorNumStr: TString50;
		textWindow: TTextWindowState;
	begin
		ioResValue := IOResult;
		if ioResValue = 0 then begin
			DisplayIOError := false;
			exit;
		end;

		DisplayIOError := true;

		Str(ioResValue, textWindow.Title);
		textWindow.Title := 'Error # ' + textWindow.Title;
		TextWindowInitState(textWindow);
		TextWindowAppend(textWindow, '$DOS Error: ');
		TextWindowAppend(textWindow, '');
		TextWindowAppend(textWindow, 'This may be caused by missing');
		TextWindowAppend(textWindow, 'ZZT files or a bad disk.  If');
		TextWindowAppend(textWindow, 'you are trying to save a game,');
		TextWindowAppend(textWindow, 'your disk may be full -- try');
		TextWindowAppend(textWindow, 'using a blank, formatted disk');
		TextWindowAppend(textWindow, 'for saving the game!');

		TextWindowDrawOpen(textWindow);
		TextWindowSelect(textWindow, false, false);
		TextWindowDrawClose(textWindow);
		TextWindowFree(textWindow);
	end;

procedure WorldUnload;
	var
		i: integer;
	begin
		BoardClose;
		for i := 0 to World.BoardCount do
			ExtMemFree(World.BoardData[i], World.BoardLen[i]);
	end;

function WorldLoad(filename, extension: TString50; titleOnly: boolean): boolean;
	var
		f: file;
		ptr: pointer;
		boardId: integer;
		loadProgress: integer;
	label OnError;
	procedure SidebarAnimateLoading;
		begin
			VideoWriteText(69, 5, ProgressAnimColors[loadProgress], ProgressAnimStrings[loadProgress]);
			loadProgress := (loadProgress + 1) and 7;
		end;
	begin
		WorldLoad := false;
		loadProgress := 0;

		SidebarClearLine(4);
		SidebarClearLine(5);
		VideoWriteText(62, 5, $1F, 'Loading.....');

		Assign(f, filename + extension);
		Reset(f, 1);

		if not DisplayIOError then begin
			WorldUnload;
			BlockRead(f, IoTmpBuf^, WORLD_FILE_HEADER_SIZE);

			if not DisplayIOError then begin
				ptr := IoTmpBuf;
				Move(ptr^, World.BoardCount, SizeOf(World.BoardCount));
				AdvancePointer(ptr, SizeOf(World.BoardCount));

				if World.BoardCount < 0 then begin
					if World.BoardCount <> -1 then begin
						VideoWriteText(62, 5, $1E, 'You need a newer');
						VideoWriteText(63, 6, $1E, 'version of ZZT!');
						goto OnError;
					end else begin
						Move(ptr^, World.BoardCount, SizeOf(World.BoardCount));
						AdvancePointer(ptr, SizeOf(World.BoardCount));
					end;
				end;

				if (World.BoardCount > MAX_BOARD) or (World.BoardCount < 0) then begin
					VideoWriteText(62, 5, $1E, 'Too many boards!');
					World.BoardCount := 0;
					exit;
				end;

				Move(ptr^, World.Info, SizeOf(World.Info));
				AdvancePointer(ptr, SizeOf(World.Info));

				if titleOnly then begin
					World.BoardCount := 0;
					World.Info.CurrentBoard := 0;
					World.Info.IsSave := true;
				end;

				for boardId := 0 to World.BoardCount do begin
					SidebarAnimateLoading;
					BlockRead(f, World.BoardLen[boardId], 2);
					if ExtMemGet(World.BoardData[boardId], World.BoardLen[boardId]) then begin
						case EnsureIoTmpBufSize(World.BoardLen[boardId]) of
							0, 1: begin end;
							2: RunError(203);
						end;

						BlockRead(f, IoTmpBuf^, World.BoardLen[boardId]);
						ExtMemWrite(World.BoardData[boardId], IoTmpBuf^, World.BoardLen[boardId]);
					end else RunError(203);
				end;

				BoardOpen(World.Info.CurrentBoard);
				LoadedGameFileName := filename;
				WorldLoad := true;

				HighScoresLoad;
{$IFDEF DEBUGWND}
				{ BoardEnter is only called for play-boards, not title-boards. }
				if titleOnly and DebugCompatEnabled then
					DebugBoardIllegalElements;
{$ENDIF}
				SidebarClearLine(5);
			end;
		end;

	OnError:
		Close(f);
	end;

procedure WorldSave(filename, extension: TString50);
	var
		f: file;
		i: integer;
		unk1: integer;
		ptr: pointer;
		version: integer;
	label OnError;
	begin
		BoardClose;
		VideoWriteText(63, 5, $1F, 'Saving...');

		Assign(f, filename + extension);
		Rewrite(f, 1);

		if not DisplayIOError then begin
			ptr := IoTmpBuf;
			FillChar(IoTmpBuf^, WORLD_FILE_HEADER_SIZE, 0);
			version := -1;
			Move(version, ptr^, SizeOf(version));
			AdvancePointer(ptr, SizeOf(version));

			Move(World.BoardCount, ptr^, SizeOf(World.BoardCount));
			AdvancePointer(ptr, SizeOf(World.BoardCount));

			Move(World.Info, ptr^, SizeOf(World.Info));
			AdvancePointer(ptr, SizeOf(World.Info));

			BlockWrite(f, IoTmpBuf^, WORLD_FILE_HEADER_SIZE);
			if DisplayIOError then goto OnError;

			for i := 0 to World.BoardCount do begin
				BlockWrite(f, World.BoardLen[i], 2);
				if DisplayIOError then goto OnError;

				ExtMemRead(World.BoardData[i], IoTmpBuf^, World.BoardLen[i]);
				BlockWrite(f, IoTmpBuf^, World.BoardLen[i]);
				if DisplayIOError then goto OnError;
			end;
		end;

		BoardOpen(World.Info.CurrentBoard);
		SidebarClearLine(5);
		Close(f);
		exit;

	OnError:
		Close(f);
		Erase(f);
		BoardOpen(World.Info.CurrentBoard);
		SidebarClearLine(5);
	end;

procedure GameWorldSave(prompt: TString50; var filename: TString50; extension: TString50);
	var
		newFilename: TString50;
	begin
		newFilename := filename;
		SidebarPromptString(prompt, extension, newFilename, PROMPT_ALPHANUM);
		if (InputKeyPressed <> KEY_ESCAPE) and (Length(newFilename) <> 0) then begin
			filename := newFilename;
			if extension = '.ZZT' then
				World.Info.Name := filename;
			WorldSave(filename, extension);
		end;
	end;

function GameWorldLoad(extension: TString50): boolean;
	var
		title: TString50;
		entryName: string;
	begin
		{ As directory listings can take up a lot of memory, }
		{ free IoTmpBuf for the duration - the data will be }
		{ unloaded later anyway. - asie }
		FreeMem(IoTmpBuf, IoTmpBufSize);

		if extension = '.ZZT' then
			title := 'ZZT Worlds'
		else
			title := 'Saved Games';
		GameWorldLoad := false;

		entryName := FileSelect(title, extension);
		GetMem(IoTmpBuf, IoTmpBufSize);

		if Length(entryName) > 0 then begin
			if WorldLoad(entryName, extension, false) then
				GameWorldLoad := true
			else begin
				WorldCreate;
				PauseOnError;
			end;
			TransitionDrawToFill(#219, $44);
		end;
	end;

procedure CopyStatDataToTextWindow(statId: integer; var state: TTextWindowState);
	var
		dataStr: string;
		dataChr: char;
		i: integer;
		dataStrLen: byte;
	begin
		with Board.Stats[statId] do begin
			TextWindowInitState(state);
			dataStrLen := 0;

			for i := 0 to (DataLen - 1) do begin
				{$IFNDEF FPC}
				{ On Turbo Pascal, the array pointer is actually }
				{ a poiter to a string. }
				dataChr := Data^[i];
				{$ELSE}
				dataChr := Data[i];
				{$ENDIF}
				if dataChr = KEY_ENTER then begin
					dataStr[0] := Chr(dataStrLen);
					TextWindowAppend(state, dataStr);
					dataStrLen := 0;
				end else begin
					Inc(dataStrLen);
					dataStr[dataStrLen] := dataChr;
				end;
			end;

			if dataStrLen > 0 then begin
				dataStr[0] := Chr(dataStrLen);
				TextWindowAppend(state, dataStr);
			end;
		end;
	end;

procedure AddStat(tx, ty: integer; element: byte; color, tcycle: integer; template: TStat);
	begin
		if Board.StatCount < MAX_STAT then begin
			Inc(Board.StatCount);
			Board.Stats[Board.StatCount] := template;
			with Board.Stats[Board.StatCount] do begin
				X := tx;
				Y := ty;
				Cycle := tcycle;
				Under := Board.Tiles[tx][ty];
				DataPos := 0;
			end;

			if (template.Data <> nil) and (template.DataLen > 0) then begin
				GetMem(Board.Stats[Board.StatCount].Data, template.DataLen);
				Move(template.Data^, Board.Stats[Board.StatCount].Data^, template.DataLen);
			end;

			if ElementDefs[Board.Tiles[tx][ty].Element].PlaceableOnTop then
				Board.Tiles[tx][ty].Color := (color and $0F) + (Board.Tiles[tx][ty].Color and $70)
			else
				Board.Tiles[tx][ty].Color := color;
			Board.Tiles[tx][ty].Element := element;

			if ty > 0 then
				BoardDrawTile(tx, ty);
		end;
	end;

procedure FreeStatDataMem(statId: integer; showError: boolean);
	var
		i: integer;
	begin
		with Board.Stats[statId] do begin
			if DataLen <> 0 then begin
				for i := 1 to Board.StatCount do begin
					if (Board.Stats[i].Data = Data) and (i <> statId) then begin
{$IFDEF DEBUGWND}
						if (showError) and (DebugCompatEnabled) then
							DebugShowElementMessage('Illegal double free', x, y);
{$ENDIF}
						exit;
					end;
				end;
				FreeMem(Data, DataLen);
			end;
		end;
	end;

procedure RemoveStat(statId: integer);
	var
		i: integer;
	begin
		FreeStatDataMem(statId, false);

		with Board.Stats[statId] do begin
			if statId < CurrentStatTicked then
				Dec(CurrentStatTicked);

			Board.Tiles[X][Y] := Under;
			if Y > 0 then
				BoardDrawTile(X, Y);

			for i := 1 to Board.StatCount do begin
				if Board.Stats[i].Follower >= statId then begin
					if Board.Stats[i].Follower = statId then
						Board.Stats[i].Follower := -1
					else
						Dec(Board.Stats[i].Follower);
				end;

				if Board.Stats[i].Leader >= statId then begin
					if Board.Stats[i].Leader = statId then
						Board.Stats[i].Leader := -1
					else
						Dec(Board.Stats[i].Leader);
				end;
			end;

			for i := (statId + 1) to Board.StatCount do
				Board.Stats[i - 1] := Board.Stats[i];
			Dec(Board.StatCount);
		end;
	end;

{$IFDEF CPU86}
{ GetStatIdAt - hand-rolled ASM version }
{$IFNDEF FPC}
function GetStatIdAt(tx, ty: integer): integer;
	var
		sc: integer;
		st: word;
	begin
		{ Work around TP 5.5 flaw }
		sc := Board.StatCount;
		st := Ofs(Board.Stats);

		inline(
			$8B/$46/<tx/ { MOV AX, tx }
			$0B/$46/<ty/ { OR AX, ty }
			$25/$00/$FF/ { AND AX, 0xFF00 }
			$74/$02/ { JZ func_valid_range }
			$EB/$1E/ { JMP func_notfound }
			{ func_valid_range: }
			$8B/$5E/<ty/ { MOV BX, ty }
			$B1/$08/ { MOV CL, 0x8 }
			$D3/$E3/ { SHL BX, CL }
			$0B/$5E/<tx/ { OR BX, tx }
			$8B/$7E/<st/ { MOV DI, Board.Stats }
			$8B/$4E/<sc/ { MOV CX, [Board.StatCount] }
			$31/$C0/ { XOR AX, AX }
			{ func_loop: }
			$39/$1D/ { CMP [DI], BX }
			$74/$0B/ { JZ func_exit }
			$83/$C7/SizeOf(TStat)/ { ADD DI, SizeOf(TStat) }
			$40/ { INC AX }
			$39/$C8/ { CMP AX, CX }
			$7E/$F4/ { JLE func_loop }
			{ func_notfound: }
			$B8/$FF/$FF/ { MOV AX, 0xFFFF }
			{ func_finish: }
			{ Another TP 5.5 workaround... }
			$89/$46/$FE { MOV [return value], AX }
		);
	end;
{$ELSE}
function GetStatIdAt(tx, ty: integer): integer;
	assembler;
	label func_valid_range;
	label func_loop;
	label func_notfound;
	label func_finish;
	asm
		mov ax, tx
		or ax, ty
		and ax, 0FF00h
		jz func_valid_range
		jmp func_notfound
	func_valid_range:
		mov bx, ty
		mov cl, 8
		shl bx, cl
		or bx, tx
		mov di, offset Board.Stats
		mov cx, [Board.StatCount]
		xor ax, ax
	func_loop:
		cmp [di], bx
		je func_finish
		add di, SizeOf(TStat)
		inc ax
		cmp ax, cx
		jle func_loop
	func_notfound:
		mov ax, 0FFFFh
	func_finish:
	end ['ax', 'bx', 'cx', 'di'];
{$ENDIF}

{$ELSE}
function GetStatIdAt(tx, ty: integer): integer;
	var
		i: integer;
	begin
		i := -1;
		repeat
			Inc(i);
		until ((Board.Stats[i].X = tx) and (Board.Stats[i].Y = ty)) or (i > Board.StatCount);

		if i > Board.StatCount then
			GetStatIdAt := -1
		else
			GetStatIdAt := i;
	end;
{$ENDIF}

function BoardPrepareTileForPlacement(x, y: integer): boolean;
	var
		statId: integer;
		result: boolean;
	begin
		statId := GetStatIdAt(x, y);
		if statId > 0 then begin
			RemoveStat(statId);
			result := true;
		end else if statId < 0 then begin
			if not ElementDefs[Board.Tiles[x][y].Element].PlaceableOnTop then
				Board.Tiles[x][y].Element := E_EMPTY;
			result := true;
		end else begin { statId = 0 (player) cannot be modified }
			result := false;
		end;
		BoardDrawTile(x, y);
		BoardPrepareTileForPlacement := result;
	end;

procedure MoveStat(statId: integer; newX, newY: integer);
	var
		iUnder: TTile;
		ix, iy: integer;
		oldX, oldY: integer;
		oldBgColor: integer;
	begin
		with Board.Stats[statId] do begin
			oldBgColor := Board.Tiles[newX][newY].Color and $F0;

			iUnder := Under;
			Under := Board.Tiles[newX][newY];

			if Board.Tiles[X][Y].Element = E_PLAYER then
				Board.Tiles[newX][newY].Color := Board.Tiles[X][Y].Color
			else if Board.Tiles[newX][newY].Element = E_EMPTY then
				Board.Tiles[newX][newY].Color := Board.Tiles[X][Y].Color and $0F
			else
				Board.Tiles[newX][newY].Color := (Board.Tiles[X][Y].Color and $0F) + (Board.Tiles[newX][newY].Color and $70);

			Board.Tiles[newX][newY].Element := Board.Tiles[X][Y].Element;
			Board.Tiles[X][Y] := iUnder;

			oldX := X;
			oldY := Y;
			X := newX;
			Y := newY;

			BoardDrawTile(X, Y);
			BoardDrawTile(oldX, oldY);

			if (statId = 0) and Board.Info.IsDark and (World.Info.TorchTicks > 0) then begin
				if (Sqr(oldX-X) + Sqr(oldY-Y)) = 1 then begin
					for ix := (X - TORCH_DX - 3) to (X + TORCH_DX + 3) do
						if (ix >= 1) and (ix <= BOARD_WIDTH) then
							for iy := (Y - TORCH_DY - 3) to (Y + TORCH_DY + 3) do
								if (iy >= 1) and (iy <= BOARD_HEIGHT) then
									if (((Sqr(ix-oldX))+(Sqr(iy-oldY)*2)) < TORCH_DIST_SQR) xor
										(((Sqr(ix-newX))+(Sqr(iy-newY)*2)) < TORCH_DIST_SQR) then
										BoardDrawTile(ix, iy);
				end else begin
					DrawPlayerSurroundings(oldX, oldY, 0);
					DrawPlayerSurroundings(X, Y, 0);
				end;
			end;

		end;
	end;

procedure PopupPromptString(question: string; var buffer: TString50; maxLen: integer);
	var
		x, y: integer;
	begin
		VideoWriteText(3, 18, $4F, TextWindowStrTop);
		VideoWriteText(3, 19, $4F, TextWindowStrText);
		VideoWriteText(3, 20, $4F, TextWindowStrSep);
		VideoWriteText(3, 21, $4F, TextWindowStrText);
		VideoWriteText(3, 22, $4F, TextWindowStrText);
		VideoWriteText(3, 23, $4F, TextWindowStrBottom);
		VideoWriteText(4 + (TextWindowWidth - Length(question)) div 2, 19, $4F, question);
		buffer := '';
		{ x = x, y = width }
		if maxLen > (TextWindowWidth - 8) then y := (TextWindowWidth - 8) else y := maxLen;
		x := 6 + (((TextWindowWidth - 8) - y) shr 1);
		PromptString(x, 22, $4F, $4E, y, maxLen, PROMPT_ANY, buffer);
		for y := 18 to 23 do
			for x := 3 to (TextWindowWidth + 3) do
				BoardDrawTile(x + 1, y + 1);
	end;

function Signum(val: integer): integer;
	begin
		if val > 0 then
			Signum := 1
		else if val < 0 then
			Signum := -1
		else
			Signum := 0;
	end;

function Difference(a, b: integer): integer;
	begin
		if (a - b) >= 0 then
			Difference := a - b
		else
			Difference := b - a;
	end;

procedure GameUpdateSidebar;
	var
		numStr: string[8];
		i: integer;
	begin
		if GameStateElement = E_PLAYER then begin
			if Board.Info.TimeLimitSec > 0 then begin
				VideoWriteText(64, 6, $1E, '   Time:');
				Str(Board.Info.TimeLimitSec - World.Info.BoardTimeSec, numStr);
				VideoWriteText(72, 6, $1E, numStr + ' ');
			end else begin
				SidebarClearLine(6);
			end;

			if World.Info.Health < 0 then
				World.Info.Health := 0;

			Str(World.Info.Health, numStr);
			VideoWriteText(72, 7, $1E, numStr + ' ');
			Str(World.Info.Ammo, numStr);
			VideoWriteText(72, 8, $1E, numStr + '  ');
			Str(World.Info.Torches, numStr);
			VideoWriteText(72, 9, $1E, numStr + ' ');
			Str(World.Info.Gems, numStr);
			VideoWriteText(72, 10, $1E, numStr + ' ');
			Str(World.Info.Score, numStr);
			VideoWriteText(72, 11, $1E, numStr + ' ');

			if World.Info.TorchTicks = 0 then
				VideoWriteText(75, 9, $16, '    ')
			else begin
				for i := 2 to 5 do begin
					if i <= ((World.Info.TorchTicks * 5) div TORCH_DURATION) then
						VideoWriteText(73 + i, 9, $16, #177)
					else
						VideoWriteText(73 + i, 9, $16, #176);
				end;
			end;

			for i := 1 to 7 do begin
				if World.Info.Keys[i] then
					VideoWriteText(71 + i, 12, $18 + i, ElementDefs[E_KEY].Character)
				else
					VideoWriteText(71 + i, 12, $1F, ' ');
			end;

			if SoundEnabled then
				VideoWriteText(65, 15, $1F, ' Be quiet')
			else
				VideoWriteText(65, 15, $1F, ' Be noisy');

			if DebugEnabled then begin
				Str(MemAvail, numStr);
				VideoWriteText(62, 3, $1E, 'm' + numStr + ' ');
				if ExtMemEmsActive then begin
					Str(ExtMemEmsAvailPages, numstr);
					VideoWriteText(70, 3, $1E, 'e' + numStr + 'p ');
				end;
				if ExtMemXmsActive then begin
					Str(ExtMemXmsAvail, numStr);
					VideoWriteText(62, 4, $1E, 'x' + numStr + ' ');
				end;
			end;
		end;
	end;

procedure DisplayMessage(time: integer; message: string);
	begin
		if GetStatIdAt(0, 0) <> -1 then begin
			RemoveStat(GetStatIdAt(0, 0));
			BoardDrawBorder;
		end;

		if Length(message) <> 0 then begin
			AddStat(0, 0, E_MESSAGE_TIMER, 0, 1, StatTemplateDefault);
			Board.Stats[Board.StatCount].P2 := Time div (TickTimeDuration + 1);
			Board.Info.Message := message;
		end;
	end;

procedure DamageStat(attackerStatId: integer);
	var
		oldX, oldY: integer;
	begin
		with Board.Stats[attackerStatId] do begin
			if attackerStatId = 0 then begin
				if World.Info.Health > 0 then begin
					Dec(World.Info.Health, 10);

					GameUpdateSidebar;
					DisplayMessage(100, 'Ouch!');

					Board.Tiles[X][Y].Color := $70 + (ElementDefs[E_PLAYER].Color and $0F);

					if World.Info.Health > 0 then begin
						World.Info.BoardTimeSec := 0;
						if Board.Info.ReenterWhenZapped then begin
							SoundQueue(4, #32#1#35#1#39#1#48#1#16#1);

							{ Move player to start }
							Board.Tiles[X][Y].Element := E_EMPTY;
							BoardDrawTile(X, Y);
							oldX := X;
							oldY := Y;
							X := Board.Info.StartPlayerX;
							Y := Board.Info.StartPlayerY;
							DrawPlayerSurroundings(oldX, oldY, 0);
							DrawPlayerSurroundings(X, Y, 0);

							GamePaused := true;
						end;
						SoundQueue(4, #16#1#32#1#19#1#35#1);
					end else begin
						SoundQueue(5, #32#3#35#3#39#3#48#3#39#3#42#3#50#3#55#3#53#3#56#3#64#3#69#3#16#10);
					end;
				end;
			end else begin
				case Board.Tiles[X][Y].Element of
					E_BULLET: SoundQueue(3, #32#1);
					E_OBJECT: begin end;
				else
					SoundQueue(3, #64#1#16#1#80#1#48#1)
				end;
				RemoveStat(attackerStatId);
			end;
		end;
	end;

procedure BoardDamageTile(x, y: integer);
	var
		statId: integer;
	begin
		statId := GetStatIdAt(x, y);
		if statId <> -1 then begin
			DamageStat(statId);
		end else begin
			Board.Tiles[x][y].Element := E_EMPTY;
			BoardDrawTile(x, y);
		end;
	end;

procedure BoardAttack(attackerStatId: integer; x, y: integer);
	begin
		if (attackerStatId = 0) and (World.Info.EnergizerTicks > 0) then begin
			Inc(World.Info.Score, ElementDefs[Board.Tiles[x][y].Element].ScoreValue);
			GameUpdateSidebar;
		end else begin
			DamageStat(attackerStatId);
		end;

		if (attackerStatId > 0) and (attackerStatId <= CurrentStatTicked) then
			Dec(CurrentStatTicked);

		if (Board.Tiles[x][y].Element = E_PLAYER) and (World.Info.EnergizerTicks > 0) then begin
			World.Info.Score := ElementDefs[Board.Tiles[Board.Stats[attackerStatId].X][Board.Stats[attackerStatId].Y].Element]
				.ScoreValue + World.Info.Score;
			GameUpdateSidebar;
		end else begin
			BoardDamageTile(x, y);
			SoundQueue(2, #16#1);
		end;
	end;

function BoardShoot(element: byte; tx, ty, deltaX, deltaY: integer; source: integer): boolean;
	begin
		if ElementDefs[Board.Tiles[tx + deltaX][ty + deltaY].Element].Walkable
			or (Board.Tiles[tx + deltaX][ty + deltaY].Element = E_WATER) then
		begin
			AddStat(tx + deltaX, ty + deltaY, element, ElementDefs[element].Color, 1, StatTemplateDefault);
			with Board.Stats[Board.StatCount] do begin
				P1 := source;
				StepX := deltaX;
				StepY := deltaY;
				P2 := 100;
			end;
			BoardShoot := true;
		end else if (Board.Tiles[tx + deltaX][ty + deltaY].Element = E_BREAKABLE)
			or (
				ElementDefs[Board.Tiles[tx + deltaX][ty + deltaY].Element].Destructible
				and ((Board.Tiles[tx + deltaX][ty + deltaY].Element = E_PLAYER) = Boolean(source))
				and (World.Info.EnergizerTicks <= 0)
			) then
		begin
			BoardDamageTile(tx + deltaX, ty + deltaY);
			SoundQueue(2, #16#1);
			BoardShoot := true;
		end else begin
			BoardShoot := false;
		end;
	end;

procedure CalcDirectionRnd(var deltaX, deltaY: integer);
	begin
		deltaX := Random(3) - 1;

		if deltaX = 0 then
			deltaY := Random(2) * 2 - 1
		else
			deltaY := 0;
	end;

procedure CalcDirectionSeek(x, y: integer; var deltaX, deltaY: integer);
	begin
		deltaX := 0;
		deltaY := 0;

		if (Random(2) < 1) or (Board.Stats[0].Y = y) then
			deltaX := Signum(Board.Stats[0].X - x);

		if deltaX = 0 then
			deltaY := Signum(Board.Stats[0].Y - y);

		if World.Info.EnergizerTicks > 0 then begin
			deltaX := -deltaX;
			deltaY := -deltaY;
		end;
	end;

procedure TransitionDrawBoardChange;
	begin
		TransitionDrawToFill(#219, $05);
		TransitionDrawToBoard;
	end;

procedure BoardEnter;
	begin
		Board.Info.StartPlayerX := Board.Stats[0].X;
		Board.Info.StartPlayerY := Board.Stats[0].Y;

		if Board.Info.IsDark and MessageHintTorchNotShown then begin
			DisplayMessage(200, 'Room is dark - you need to light a torch!');
			MessageHintTorchNotShown := false;
		end;

		World.Info.BoardTimeSec := 0;
		GameUpdateSidebar;

{$IFDEF DEBUGWND}
		if DebugCompatEnabled then
			DebugBoardIllegalElements;
{$ENDIF}
	end;

procedure BoardPassageTeleport(x, y: integer);
	var
		oldBoard: integer;
		col: byte;
		ix, iy: integer;
		newX, newY: integer;
	begin
		col := Board.Tiles[x][y].Color;

		oldBoard := World.Info.CurrentBoard;
		BoardChange(Board.Stats[GetStatIdAt(x, y)].P3);

		newX := 0;
		for ix := 1 to BOARD_WIDTH do
			for iy := 1 to BOARD_HEIGHT do
				if (Board.Tiles[ix][iy].Element = E_PASSAGE) and (Board.Tiles[ix][iy].Color = col) then begin
					newX := ix;
					newY := iy;
				end;

		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_EMPTY;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := 0;
		if newX <> 0 then begin
			Board.Stats[0].X := newX;
			Board.Stats[0].Y := newY;
		end;

		GamePaused := true;
		SoundQueue(4, #48#1#52#1#55#1#49#1#53#1#56#1#50#1#54#1#57#1#51#1#55#1#58#1#52#1#56#1#64#1);
		TransitionDrawBoardChange;
		BoardEnter;
	end;

function DebugPromptParseInt(input: TString50; offset: integer; defaultValue: integer): integer;
	var
		substr: TString50;
		result, code: integer;
	begin
		if Length(input) >= (offset + 2) then begin
			substr := Copy(input, offset + 2, Length(input));
			Val(substr, result, code);
			DebugPromptParseInt := result;
		end else begin
			DebugPromptParseInt := defaultValue;
		end;
	end;

function DebugPromptParseElem(input: TString50; offset: integer): integer;
	var
		substr: TString50;
		i: integer;
	begin
		substr := '';
		for i := offset + 2 to Length(input) do
			substr := substr + UpCase(input[i]);
		if substr = 'ALL' then begin
			DebugPromptParseElem := -1;
			exit;
		end;
		for i := 0 to MAX_ELEMENT do begin
			if substr = OopStringToWord(ElementDefs[i].Name) then begin
				DebugPromptParseElem := i;
				exit;
			end;
		end;
		DebugPromptParseElem := E_BOARD_EDGE;
	end;

function DebugPromptParseColor(input: TString50; offset: integer): integer;
	var
		substr: TString50;
		i: integer;
	begin
		substr := '';
		for i := offset + 2 to Length(input) do
			substr := substr + UpCase(input[i]);
		for i := 1 to 7 do begin
			if substr = OopStringToWord(ColorNames[i]) then begin
				DebugPromptParseColor := i;
				exit;
			end;
		end;
		DebugPromptParseColor := -1;
	end;

function DebugPromptStarts(input: TString50; cmp: TString50): boolean;
	var
		i: integer;
	begin
		DebugPromptStarts := Length(input) >= Length(cmp);
		for i := 1 to Length(cmp) do begin
			if input[i] <> cmp[i] then begin
				DebugPromptStarts := false;
				exit;
			end;
		end;
	end;

procedure DebugPromptFlagWindow;
	var
		i: integer;
		flagId: string[11];
		textWindow: TTextWindowState;
	begin
		textWindow.Title := 'Flags';
		TextWindowInitState(textWindow);
		for i := 1 to MAX_FLAG do begin
			Str(i, flagId);
			TextWindowAppend(textWindow, flagId + ': ' + World.Info.Flags[i]);
		end;

		TextWindowDrawOpen(textWindow);
		TextWindowSelect(textWindow, false, false);
		TextWindowDrawClose(textWindow);
		TextWindowFree(textWindow);
	end;

procedure GameDebugPrompt;
	var
		input: TString50;
		i, iMin, iMax: integer;
		btmp: byte;
		isYes: boolean; { True if not 'NO[cheat]' }
		isYesMultiplier: integer; { -1 if 'NO[cheat]', 1 otherwise }
	begin
		input := '';
		SidebarClearLine(4);
		SidebarClearLine(5);

		PromptString(63, 5, $1E, $0F, 11, 50, PROMPT_ANY, input);
		for i := 1 to Length(input) do
			input[i] := UpCase(input[i]);

		isYes := true;
		isYesMultiplier := 1;
		if Length(input) <= 0 then begin
			{ No-op. }
		end else if input[1] = '?' then begin
			{ Open help file. }
			if Length(input) >= 2 then
				input := Copy(input, 2, Length(input) - 1)
			else
				input := 'CHEAT';
			TextWindowDisplayFile(input, 'View file');
		end else if (input[1] = '+') or (input[1] = '-') then begin
			isYes := input[1] = '+';
			input := Copy(input, 2, Length(input) - 1);

			if isYes then
				WorldSetFlag(input)
			else
				WorldClearFlag(input);
		end else begin
			if (Length(input) >= 2) and (input[1] = 'N') and (input[2] = 'O') then begin
				input := Copy(input, 3, Length(input) - 2);
				isYes := false;
				isYesMultiplier := -1;
			end;

			if DebugPromptStarts(input, 'HEALTH') then
				Inc(World.Info.Health, DebugPromptParseInt(input, 6, 50) * isYesMultiplier)
			else if DebugPromptStarts(input, 'AMMO') then
				Inc(World.Info.Ammo, DebugPromptParseInt(input, 4, 5) * isYesMultiplier)
			else if DebugPromptStarts(input, 'KEYS') then begin
				i := DebugPromptParseColor(input, 4);
				if i > 0 then World.Info.Keys[i] := isYes
				else for i := 1 to 7 do World.Info.Keys[i] := isYes;
			end else if DebugPromptStarts(input, 'TORCHES') then
				Inc(World.Info.Torches, DebugPromptParseInt(input, 7, 3) * isYesMultiplier)
			else if DebugPromptStarts(input, 'TIME') then
				Dec(World.Info.BoardTimeSec, DebugPromptParseInt(input, 4, 30) * isYesMultiplier)
			else if DebugPromptStarts(input, 'GEMS') then
				Inc(World.Info.Gems, DebugPromptParseInt(input, 4, 5) * isYesMultiplier)
			else if input = 'DARK' then begin
				Board.Info.IsDark := isYes;
				TransitionDrawToBoard;
			end else if input = 'BLINK' then begin
				VideoSetBlink(isYes);
			end else if input = 'DEBUG' then begin
				DebugEnabled := isYes;
{$IFDEF DEBUGWND}
			end else if input = 'DCOMPAT' then begin
				DebugCompatEnabled := isYes;
{$ENDIF}
{$IFDEF EXTCHEAT}
			end else if DebugPromptStarts(input, 'SHOW') then begin
				i := DebugPromptParseElem(input, 4);
				if i >= 0 then begin
					iMin := i;
					iMax := i;
				end else begin
					iMin := 0;
					if isYes then
						iMax := -1 { Block SHOW ALL }
					else
						iMax := MAX_ELEMENT;
				end;
				for i := iMin to iMax do begin
					btmp := Byte(isYes) shl 7;
					if btmp <> CheatColorModifiers[i] then begin
						CheatColorModifiers[i] := btmp;
						btmp := Byte(CheatCharModifiers[i]);
						CheatCharModifiers[i] := ElementDefs[i].Character;
						ElementDefs[i].Character := Char(btmp);
					end;
				end;
				TransitionDrawToBoard;
			end else if input = 'CLIP' then begin
				CheatNoClip := not isYes;
			end else if input = 'FREEZE' then begin
				CheatFreeze := isYes;
			end else if input = 'FLAGS' then begin
				DebugPromptFlagWindow;
{$ENDIF}
			end else if isYes then begin
				{ Non-toggleables. }
{$IFDEF EXTCHEAT}
				if input = 'PASSAGE' then begin
					if GameStateElement = E_PLAYER then begin
						BoardChange(EditorSelectBoard('Teleport to', World.Info.CurrentBoard, false));
						GamePaused := true;
						TransitionDrawBoardChange;
						BoardEnter;
					end;
				end else
{$ENDIF}
				if DebugPromptStarts(input, 'SPEED') then begin
					i := DebugPromptParseInt(input, 5, -1);
					if (i >= 0) and (i <= 8) then begin
						TickSpeed := i;
					end else begin
						SidebarPromptSlider(true, 63, 3, 'Game speed:;FS', TickSpeed);
						SidebarClearLine(3);
					end;
					TickTimeDuration := TickSpeed * 2;
					SoundBlockQueueing := false;
					InputKeyPressed := #0;
				end else if (input = 'ZAP') then begin
					for i := 0 to 3 do begin
						BoardDamageTile(Board.Stats[0].X + NeighborDeltaX[i], Board.Stats[0].Y + NeighborDeltaY[i]);
						Board.Tiles[Board.Stats[0].X + NeighborDeltaX[i]][Board.Stats[0].Y + NeighborDeltaY[i]].Element := E_EMPTY;
						BoardDrawTile(Board.Stats[0].X + NeighborDeltaX[i], Board.Stats[0].Y + NeighborDeltaY[i]);
					end;
				end;
			end;
		end;

		SoundQueue(10, #39#4);
		SidebarClearLine(4);
		SidebarClearLine(5);
		GameUpdateSidebar;
	end;

procedure GameAboutScreen;
	begin
		TextWindowDisplayFile('ABOUT.HLP', 'About ZZT...');
	end;

procedure GameOnStart;
	var
		f: file;
	begin
		GameAboutScreen;
		if Length(StartupWorldFileName) <> 0 then begin
			if FileExists(StartupWorldFileName + '.ZZT') and WorldLoad(StartupWorldFileName, '.ZZT', true) then begin
				SidebarClearLine(8);
				VideoWriteText(69, 8, $1F, StartupWorldFileName);
			end else begin
				WorldCreate;
			end;
		end;
		ReturnBoardId := World.Info.CurrentBoard;
		BoardChange(0);
	end;

procedure GamePlayLoop(boardChanged: boolean);
	var
		exitLoop: boolean;
		pauseBlink: boolean;
	procedure GameDrawSidebar;
		begin
			SidebarClear;
			SidebarClearLine(0);
			SidebarClearLine(1);
			SidebarClearLine(2);
			VideoWriteText(61, 0, $1F, '    - - - - -      ');
			VideoWriteText(62, 1, $70, '      ZZT*     ');
			VideoWriteText(61, 2, $1F, '    - - - - -      ');
			if GameStateElement = E_PLAYER then begin
				VideoWriteText(64, 7, $1E, ' Health:');
				VideoWriteText(64, 8, $1E, '   Ammo:');
				VideoWriteText(64, 9, $1E, 'Torches:');
				VideoWriteText(64, 10, $1E, '   Gems:');
				VideoWriteText(64, 11, $1E, '  Score:');
				VideoWriteText(64, 12, $1E, '   Keys:');
				VideoWriteText(62, 7, $1F, ElementDefs[E_PLAYER].Character);
				VideoWriteText(62, 8, $1B, ElementDefs[E_AMMO].Character);
				VideoWriteText(62, 9, $16, ElementDefs[E_TORCH].Character);
				VideoWriteText(62, 10, $1B, ElementDefs[E_GEM].Character);
				VideoWriteText(62, 12, $1F, ElementDefs[E_KEY].Character);
				VideoWriteText(62, 14, $70, ' T ');
				VideoWriteText(65, 14, $1F, ' Torch');
				VideoWriteText(62, 15, $30, ' B ');
				VideoWriteText(62, 16, $70, ' H ');
				VideoWriteText(65, 16, $1F, ' Help');
				VideoWriteText(67, 18, $30, ' '#24#25#26#27' ');
				VideoWriteText(72, 18, $1F, ' Move');
				VideoWriteText(61, 19, $70, ' Shift '#24#25#26#27' ');
				VideoWriteText(72, 19, $1F, ' Shoot');
				VideoWriteText(62, 21, $70, ' S ');
				VideoWriteText(65, 21, $1F, ' Save game');
				VideoWriteText(62, 22, $30, ' P ');
				VideoWriteText(65, 22, $1F, ' Pause');
				VideoWriteText(62, 23, $70, ' Q ');
				VideoWriteText(65, 23, $1F, ' Quit');
			end else if GameStateElement = E_MONITOR then begin
				SidebarPromptSlider(false, 66, 21, 'Game speed:;FS', TickSpeed);
				VideoWriteText(62, 21, $70, ' S ');
				VideoWriteText(62, 7, $30, ' W ');
				VideoWriteText(65, 7, $1E, ' World:');

				if Length(World.Info.Name) <> 0 then
					VideoWriteText(69, 8, $1F, World.Info.Name)
				else
					VideoWriteText(69, 8, $1F, 'Untitled');

				VideoWriteText(62, 11, $70, ' P ');
				VideoWriteText(65, 11, $1F, ' Play');
				VideoWriteText(62, 12, $30, ' R ');
				VideoWriteText(65, 12, $1E, ' Restore game');
				VideoWriteText(62, 13, $70, ' Q ');
				VideoWriteText(65, 13, $1E, ' Quit');
				VideoWriteText(62, 16, $30, ' A ');
				VideoWriteText(65, 16, $1F, ' About ZZT!');
				VideoWriteText(62, 17, $70, ' H ');
				VideoWriteText(65, 17, $1E, ' High Scores');

{$IFDEF EDITOR}
				if EditorEnabled then begin
					VideoWriteText(62, 18, $30, ' E ');
					VideoWriteText(65, 18, $1E, ' Board Editor');
				end;
{$ENDIF}
			end;
		end;
	begin
		GameDrawSidebar;
		GameUpdateSidebar;

		if JustStarted then begin
			GameOnStart;
			JustStarted := false;
		end;

		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := GameStateElement;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[GameStateElement].Color;

		if GameStateElement = E_MONITOR then begin
			DisplayMessage(0, '');
			VideoWriteText(62, 5, $1B, 'Pick a command:');
		end;

		if boardChanged then
			TransitionDrawBoardChange;

		TickTimeDuration := TickSpeed * 2;
		GamePlayExitRequested := false;
		exitLoop := false;

		CurrentTick := Random(100);
		CurrentStatTicked := Board.StatCount + 1;

		repeat
			if GamePaused then begin
				if SoundHasTimeElapsed(TickTimeCounter, 25) then
					pauseBlink := not pauseBlink;

				if pauseBlink then begin
					VideoWriteText(Board.Stats[0].X - 1, Board.Stats[0].Y - 1,
						ElementDefs[E_PLAYER].Color, ElementDefs[E_PLAYER].Character);
				end else begin
					if Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element = E_PLAYER then
						VideoWriteText(Board.Stats[0].X - 1, Board.Stats[0].Y - 1, $0F, ' ')
					else
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
				end;

				VideoWriteText(64, 5, $1F, 'Pausing...');
				InputUpdate;

				case UpCase(InputKeyPressed) of KEY_ESCAPE, 'Q': begin
					GamePromptEndPlay;
				end; end;

				if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
					ElementDefs[Board.Tiles[Board.Stats[0].X + InputDeltaX][Board.Stats[0].Y + InputDeltaY].Element].TouchProc(
						Board.Stats[0].X + InputDeltaX, Board.Stats[0].Y + InputDeltaY, 0, InputDeltaX, InputDeltaY);
				end;

				if ((InputDeltaX <> 0) or (InputDeltaY <> 0))
					and ElementDefs[Board.Tiles[Board.Stats[0].X + InputDeltaX][Board.Stats[0].Y + InputDeltaY].Element].Walkable
				then begin
					{ Move player }
					if Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element = E_PLAYER then
						MoveStat(0, Board.Stats[0].X + InputDeltaX, Board.Stats[0].Y + InputDeltaY)
					else begin
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
						Board.Stats[0].X := Board.Stats[0].X + InputDeltaX;
						Board.Stats[0].Y := Board.Stats[0].Y + InputDeltaY;
						Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_PLAYER;
						Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[E_PLAYER].Color;
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
						DrawPlayerSurroundings(Board.Stats[0].X, Board.Stats[0].Y, 0);
						DrawPlayerSurroundings(Board.Stats[0].X - InputDeltaX, Board.Stats[0].Y - InputDeltaY, 0);
					end;

					{ Unpause }
					GamePaused := false;
					SidebarClearLine(5);
					CurrentTick := Random(100);
					CurrentStatTicked := Board.StatCount + 1;
					World.Info.IsSave := true;
				end;

			end else begin { not GamePaused }
				if CurrentStatTicked <= Board.StatCount then begin
					with Board.Stats[CurrentStatTicked] do begin
						if (Cycle <> 0) and ((CurrentTick mod Cycle) = (CurrentStatTicked mod Cycle)) then
							ElementDefs[Board.Tiles[X][Y].Element].TickProc(CurrentStatTicked);

						Inc(CurrentStatTicked);

{$IFDEF EXTCHEAT}
						if CheatFreeze then
							CurrentStatTicked := Board.StatCount + 1;
{$ENDIF}
					end;
				end;
			end;

			if ((CurrentStatTicked > Board.StatCount)) and not GamePlayExitRequested then begin
				{ all stats ticked }
				if SoundHasTimeElapsed(TickTimeCounter, TickTimeDuration) then begin
					{ next cycle }
					Inc(CurrentTick);
					if CurrentTick > 420 then
						CurrentTick := 1;
					CurrentStatTicked := 0;

					InputUpdate;
				end;
			end;
		until (exitLoop or GamePlayExitRequested) and GamePlayExitRequested;

		SoundClearQueue;

		if GameStateElement = E_PLAYER then begin
			if World.Info.Health <= 0 then begin
				HighScoresAdd(World.Info.Score);
			end;
		end else if GameStateElement = E_MONITOR then begin
			SidebarClearLine(5);
		end;

		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_PLAYER;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[E_PLAYER].Color;

		SoundBlockQueueing := false;
	end;

procedure GameTitleLoop;
	var
		boardChanged: boolean;
		startPlay: boolean;
	begin
		GameTitleExitRequested := false;
		JustStarted := true;
		ReturnBoardId := 0;
		boardChanged := true;
		repeat
			BoardChange(0);
			repeat
				GameStateElement := E_MONITOR;
				startPlay := false;
				GamePaused := false;
				GamePlayLoop(boardChanged);
				boardChanged := false;

				case UpCase(InputKeyPressed) of
					'W': begin
						if GameWorldLoad('.ZZT') then begin
							ReturnBoardId := World.Info.CurrentBoard;
							boardChanged := true;
						end;
					end;
					'P': begin
						if World.Info.IsSave and not DebugEnabled then begin
							startPlay := WorldLoad(World.Info.Name, '.ZZT', false);
							ReturnBoardId := World.Info.CurrentBoard;
						end else begin
							startPlay := true;
						end;
						if startPlay then begin
							BoardChange(ReturnBoardId);
							BoardEnter;
						end;
					end;
					'A': begin
						GameAboutScreen;
					end;
{$IFDEF EDITOR}
					'E': if EditorEnabled then begin
						EditorLoop;
						ReturnBoardId := World.Info.CurrentBoard;
						boardChanged := true;
					end;
{$ENDIF}
					'S': begin
						SidebarPromptSlider(true, 66, 21, 'Game speed:;FS', TickSpeed);
						InputKeyPressed := #0;
					end;
					'R': begin
						if GameWorldLoad('.SAV') then begin
							ReturnBoardId := World.Info.CurrentBoard;
							BoardChange(ReturnBoardId);
							startPlay := true;
						end;
					end;
					'H': begin
						HighScoresLoad;
						HighScoresDisplay(1);
					end;
					'|': begin
						GameDebugPrompt;
					end;
					KEY_ESCAPE, 'Q': begin
						GameTitleExitRequested := SidebarPromptYesNo('Quit ZZT? ', true);
					end;
				end;

				if startPlay then begin
					GameStateElement := E_PLAYER;
					GamePaused := true;
					GamePlayLoop(true);
					boardChanged := true;
				end;
			until boardChanged or GameTitleExitRequested;
		until GameTitleExitRequested;
	end;

end.
