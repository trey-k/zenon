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
unit Oop;

interface
	uses GameVars;
	function OopStringToWord(input: TString50): TString50;
	function WorldGetFlagPosition(name: TString50): integer;
	procedure WorldSetFlag(name: TString50);
	procedure WorldClearFlag(name: TString50);
	function OopSend(statId: integer; sendLabel: string; ignoreLock: boolean): boolean;
	procedure OopExecute(statId: integer; var position: integer; name: TString50);
	function OopIterateStat(statId: integer; var iStat: integer; lookup: string): boolean;

implementation
uses
{$IFDEF DEBUGWND}
DebugWnd,
{$ENDIF}
Sounds, TxtWind, Game, Elements;

{ZENON temp old FS procedures}
procedure OopMakeFile(filename: string; contents: string);
	var
		f: file of string;
	begin
		Assign(f, filename);
		Rewrite(f);
		Write(f, contents);
		Close(f);
		if DisplayIOError then begin
		end else begin
		end;
	end;

procedure OopReadFile(filename: string; var FileContents: string);
	var
		f: file of string;
	begin
		Assign(f, filename);
		Reset(f);
		Read(f, FileContents);
		Close(f);
		if DisplayIOError then begin
		end else begin
		end;
	end;
{END}

procedure OopError(statId: integer; message: string);
	begin
		with Board.Stats[statId] do begin
{$IFDEF DEBUGWND}
			if DebugEnabled then begin
				DebugShowElementMessage(message, X, Y);
				DataPos := -1;
				exit;
			end;
{$ENDIF}
			DisplayMessage(200, 'ERR: ' + message);
			SoundQueue(5, #80#10);
			DataPos := -1;
		end;
	end;

procedure OopReadChar(statId: integer; var position: integer);
	begin
		with Board.Stats[statId] do begin
			if (position >= 0) and (position < DataLen) then begin
				{$IFNDEF FPC}
				{ On Turbo Pascal, the array pointer is actually }
				{ a poiter to a string. }
				OopChar := Data^[position];
				{$ELSE}
				OopChar := Data[position];
				{$ENDIF}
				Inc(position);
			end else begin
				OopChar := #0
			end;
		end;
	end;

procedure OopReadWord(statId: integer; var position: integer);
	var
		wordPos: byte;
	begin
		wordPos := 0;
		repeat
			OopReadChar(statId, position);
		until OopChar <> ' ';
		OopChar := UpCase(OopChar);
		if (OopChar < '0') or (OopChar > '9') then begin
			while ((OopChar >= 'A') and (OopChar <= 'Z')) or (OopChar = ':')
				or ((OopChar >= '0') and (OopChar <= '9')) or (OopChar = '_') or (OopChar = '$') or (OopChar = '.') do
			begin
				if wordPos <= OOP_TOKEN_LENGTH then begin
					Inc(wordPos);
					OopWord[wordPos] := OopChar;
				end;
				OopReadChar(statId, position);
				OopChar := UpCase(OopChar);
			end;
		end;
		OopWord[0] := Chr(wordPos);
		if position > 0 then
			Dec(position);
	end;

procedure OopReadValue(statId: integer; var position: integer);
	var
		s: string[OOP_TOKEN_LENGTH];
		code: integer;
		wordPos: byte;
	begin
		wordPos := 0;
		repeat
			OopReadChar(statId, position)
		until OopChar <> ' ';

		OopChar := UpCase(OopChar);
		while (OopChar >= '0') and (OopChar <= '9') do begin
			if wordPos <= OOP_TOKEN_LENGTH then begin
				Inc(wordPos);
				s[wordPos] := OopChar;
			end;
			OopReadChar(statId, position);
			OopChar := UpCase(OopChar);
		end;

		s[0] := Chr(wordPos);
		if position > 0 then
			Dec(position);

		if Length(s) <> 0 then
			Val(s, OopValue, code)
		else
			OopValue := -1;
	end;

procedure OopSkipLine(statId: integer; var position: integer);
	begin
		repeat
			OopReadChar(statId, position);
		until (OopChar = #0) or (OopChar = #13);
	end;

function OopParseDirection(statId: integer; var position: integer; var dx, dy: integer): boolean;
	var
		iStat: integer;
		ix, iy: integer;
	begin
		with Board.Stats[statId] do begin
			OopParseDirection := true;

			if (OopWord = 'N') or (OopWord = 'NORTH') then begin
				dx := 0;
				dy := -1;
			end else if (OopWord = 'S') or (OopWord = 'SOUTH') then begin
				dx := 0;
				dy := 1;
			end else if (OopWord = 'E') or (OopWord = 'EAST') then begin
				dx := 1;
				dy := 0;
			end else if (OopWord = 'W') or (OopWord = 'WEST') then begin
				dx := -1;
				dy := 0;
			end else if (OopWord = 'I') or (OopWord = 'IDLE') then begin
				dx := 0;
				dy := 0;
			end else if (OopWord = 'SEEK') then begin
				CalcDirectionSeek(X, Y, dx, dy);
			{SEEKOBJ <number statId>|<objectname> direction constant}
			end else if (OopWord = 'SEEKOBJ') then begin
				OopReadValue(statId, position);
				if OopValue <> -1 then
					CalcDirectionSeekObj(X, Y, OopValue, dx, dy)
				else begin
					OopReadWord(statId, position);
					iStat := 0;
					if OopIterateStat(statId, iStat, OopWord) then
						CalcDirectionSeekObj(X, Y, iStat, dx, dy);
				end;
			{XY <number x> <number y>}
			end else if (OopWord = 'XY') then begin
				OopReadValue(statId, position);
				ix := OopValue;
				OopReadValue(statId, position);
				iy := OopValue;
				if (ix <> -1) and (iy <> -1) then
					CalcDirectionXY(X, Y, ix, iy, dx, dy);
			{END}
			end else if (OopWord = 'FLOW') then begin
				dx := StepX;
				dy := StepY;
			end else if (OopWord = 'RND') then begin
				CalcDirectionRnd(dx, dy)
			end else if (OopWord = 'RNDNS') then begin
				dx := 0;
				dy := Random(2) * 2 - 1;
			end else if (OopWord = 'RNDNE') then begin
				dx := Random(2);
				if dx = 0 then dy := -1 else dy := 0;
			end else if (OopWord = 'CW') then begin
				OopReadWord(statId, position);
				OopParseDirection := OopParseDirection(statId, position, dy, dx);
				dx := -dx;
			end else if (OopWord = 'CCW') then begin
				OopReadWord(statId, position);
				OopParseDirection := OopParseDirection(statId, position, dy, dx);
				dy := -dy;
			end else if (OopWord = 'RNDP') then begin
				OopReadWord(statId, position);
				OopParseDirection := OopParseDirection(statId, position, dy, dx);
				if Random(2) = 0 then
					dx := -dx
				else
					dy := -dy;
			end else if (OopWord = 'OPP') then begin
				OopReadWord(statId, position);
				OopParseDirection := OopParseDirection(statId, position, dx, dy);
				dx := -dx;
				dy := -dy;
			end else begin
				dx := 0;
				dy := 0;
				OopParseDirection := false;
			end;
		end;
	end;

procedure OopReadDirection(statId: integer; var position: integer; var dx, dy: integer);
	begin
		OopReadWord(statId, position);
		if not OopParseDirection(statId, position, dx, dy) then
			OopError(statId, 'Bad direction');
	end;

function OopFindString(statId: integer; startPos: integer; s: string): integer;
	var
		pos, wordPos, cmpPos: integer;
		maxPos: integer;
	label NoMatch;
	begin
		for pos := 1 to Length(s) do
			s[pos] := UpCase(s[pos]);
		with Board.Stats[statId] do begin
			pos := startPos;
			maxPos := DataLen - Length(s);
			while pos <= maxPos do begin
				wordPos := 1;
				cmpPos := pos;
				repeat
					{$IFNDEF FPC}
					{ On Turbo Pascal, the array pointer is actually }
					{ a poiter to a string. }
					OopChar := Data^[cmpPos];
					{$ELSE}
					OopChar := Data[cmpPos];
					{$ENDIF}
					if s[wordPos] <> UpCase(OopChar) then
						goto NoMatch;
					Inc(wordPos);
					Inc(cmpPos);
				until wordPos > Length(s);

				{ string matches }
				OopReadChar(statId, cmpPos);
				OopChar := UpCase(OopChar);
				if ((OopChar >= 'A') and (OopChar <= 'Z')) or (OopChar = '_') then begin
					{ word continues, match invalid }
				end else begin
					{ word complete, match valid }
					OopFindString := pos;
					exit;
				end;

			NoMatch:
				Inc(pos);
			end;
			OopFindString := -1;
		end;
	end;

function OopIterateStat(statId: integer; var iStat: integer; lookup: string): boolean;
	var
		pos: integer;
		found: boolean;
	begin
		Inc(iStat);
		found := false;

		if lookup = 'ALL' then begin
			if iStat <= Board.StatCount then
				found := true;
		end else if lookup = 'OTHERS' then begin
			if iStat <= Board.StatCount then begin
				if iStat <> statId then
					found := true
				else begin
					Inc(iStat);
					found := (iStat <= Board.StatCount);
				end;
			end;
		end else if lookup = 'SELF' then begin
			if (statId > 0) and (iStat <= statId) then begin
				iStat := statId;
				found := true;
			end;
		end else begin
			while (iStat <= Board.StatCount) and not found do begin
				if Board.Stats[iStat].Data <> nil then begin
					pos := 0;
					OopReadChar(iStat, pos);
					if OopChar = '@' then begin
						OopReadWord(iStat, pos);
						if OopWord = lookup then
							found := true;
					end;
				end;

				if not found then
					Inc(iStat);
			end;
		end;

		OopIterateStat := found;
	end;

function OopFindLabel(statId: integer; sendLabel: string; var iStat, iDataPos: integer; labelPrefix: string): boolean;
	var
		targetSplitPos: integer;
		unk1: integer;
		targetLookup: string[20];
		objectMessage: string[20];
		foundStat: boolean;
	label FindNextStat;
	begin
		foundStat := false;
		targetSplitPos := Pos(':', sendLabel);
		if targetSplitPos <= 0 then begin
			{ if there is no target, we only check statId }
			if iStat < statId then begin
				objectMessage := sendLabel;
				iStat := statId;
				targetSplitPos := 0;
				foundStat := true;
			end;
		end else begin
			targetLookup := Copy(sendLabel, 1, targetSplitPos - 1);
			objectMessage := Copy(sendLabel, targetSplitPos + 1, Length(sendLabel) - targetSplitPos);
		FindNextStat:
			foundStat := OopIterateStat(statId, iStat, targetLookup);
		end;

		if foundStat then begin
			if objectMessage = 'RESTART' then begin
				iDataPos := 0;
			end else begin
				iDataPos := OopFindString(iStat, 0, labelPrefix + objectMessage);
				{ if lookup target exists, there may be more stats }
				if (iDataPos < 0) and (targetSplitPos > 0) then
					goto FindNextStat;
			end;
			foundStat := iDataPos >= 0;
		end;

		OopFindLabel := foundStat;
	end;

function WorldGetFlagPosition(name: TString50): integer;
	var
		i: integer;
	begin
		WorldGetFlagPosition := -1;
		for i := 1 to MAX_FLAG do begin
			if World.Info.Flags[i] = name then
				WorldGetFlagPosition := i;
		end;
	end;

procedure WorldSetFlag(name: TString50);
	var
		i: integer;
	begin
		if WorldGetFlagPosition(name) < 0 then begin
			i := 1;
			while (i < MAX_FLAG) and (Length(World.Info.Flags[i]) <> 0) do
				Inc(i);
			World.Info.Flags[i] := name;
		end;
	end;

procedure WorldClearFlag(name: TString50);
	var
		i: integer;
	begin
		if WorldGetFlagPosition(name) >= 0 then
			World.Info.Flags[WorldGetFlagPosition(name)] := '';
	end;

function OopStringToWord(input: TString50): TString50;
	var
		output: TString50;
		i: integer;
		outPos: byte;
	begin
		output := '';
		outPos := 0;
		for i := 1 to Length(input) do begin
			if ((input[i] >= 'A') and (input[i] <= 'Z'))
				or ((input[i] >= '0') and (input[i] <= '9')) then begin
				Inc(outPos);
				output[outPos] := input[i];
			end else if ((input[i] >= 'a') and (input[i] <= 'z')) then begin
				Inc(outPos);
				output[outPos] := Chr(Ord(input[i]) - $20);
			end;
		end;
		output[0] := Chr(outPos);
		OopStringToWord := output;
	end;

function OopParseTile(var statId, position: integer; var tile: TTile): boolean;
	var
		i: integer;
		code: integer;
	label ColorFound;
	begin
		OopParseTile := false;
		tile.Color := 0;

		OopReadWord(statId, position);
		{ZENON [RND|$byte] color choices}
		if OopWord = 'RND' then begin
			tile.Color := Random(7) + $09;
			OopReadWord(statId, position);
			goto ColorFound;
		end else if OopWord[1] = '$' then begin
			Val(OopWord, tile.Color, code);
			OopReadWord(statId, position);
			goto ColorFound;
		end;
		{END}
		for i := 1 to 7 do begin
			if OopWord = OopStringToWord(ColorNames[i]) then begin
				tile.Color := i + $08;
				OopReadWord(statId, position);
				goto ColorFound;
			end;
		end;
	ColorFound:

		for i := 0 to MAX_ELEMENT do begin
			if OopWord = OopStringToWord(ElementDefs[i].Name) then begin
				OopParseTile := true;
				tile.Element := i;
				exit;
			end;
		end;
	end;

function GetColorForTileMatch(tile: TTile): byte;
	var
		defColor: byte;
	begin
		defColor := ElementDefs[tile.Element].Color;
		if defColor < COLOR_SPECIAL_MIN then
			GetColorForTileMatch := defColor and $07
		else if defColor = COLOR_WHITE_ON_CHOICE then
			GetColorForTileMatch := ((tile.Color shr 4) and $0F) + 8
		else
			GetColorForTileMatch := (tile.Color and $0F);
	end;

function FindTileOnBoard(var x, y: integer; tile: TTile): boolean;
	begin
		FindTileOnBoard := false;
		while true do begin
			Inc(x);
			if x > BOARD_WIDTH then begin
				x := 1;
				Inc(y);
				if y > BOARD_HEIGHT then
					exit;
			end;

			if Board.Tiles[x][y].Element = tile.Element then
				if ((tile.Color = 0) or (GetColorForTileMatch(Board.Tiles[x][y]) = tile.Color)) then begin
					FindTileOnBoard := true;
					exit;
				end;
		end;
	end;

procedure OopPlaceTile(x, y: integer; tile: TTile);
	var
		dstColor: byte;
	begin
		with Board.Tiles[x][y] do begin
			if Element <> E_PLAYER then begin
				dstColor := ElementDefs[tile.Element].Color;
				if dstColor >= COLOR_SPECIAL_MIN then begin
					dstColor := tile.Color;

					if dstColor = 0 then begin
						dstColor := Color;

						if dstColor = 0 then begin
							dstColor := $0F;
						end;
					end;

					if ElementDefs[tile.Element].Color = COLOR_WHITE_ON_CHOICE then
						dstColor := ((dstColor - 8) * $10) + $0F;
				end;

				if Element = tile.Element then
					Color := dstColor
				else begin
					BoardDamageTile(x, y);
					if ElementDefs[tile.Element].Cycle >= 0 then begin
						AddStat(x, y, tile.Element, dstColor, ElementDefs[tile.Element].Cycle, StatTemplateDefault);
					end else begin
						Element := tile.Element;
						Color := dstColor;
					end;
				end;

				BoardDrawTile(x, y);
			end;
		end;
	end;

function OopCheckCondition(statId: integer; var position: integer): boolean;
	var
		deltaX, deltaY: integer;
		tile: TTile;
		ix, iy: integer;
		operation: char;
		num: integer;
		code: integer;
		iVar: integer;
	begin
		with Board.Stats[statId] do begin
			if OopWord = 'NOT' then begin
				OopReadWord(statId, position);
				OopCheckCondition := not OopCheckCondition(statId, position);
			end else if OopWord = 'ALLIGNED' then begin
				OopCheckCondition := (X = Board.Stats[0].X) or (Y = Board.Stats[0].Y);
			end else if OopWord = 'CONTACT' then begin
				OopCheckCondition := (Sqr(X - Board.Stats[0].X) + Sqr(Y - Board.Stats[0].Y)) = 1;
			end else if OopWord = 'BLOCKED' then begin
				OopReadDirection(statId, position, deltaX, deltaY);
				OopCheckCondition := not ElementDefs[Board.Tiles[X + deltaX][Y + deltaY].Element].Walkable;
			end else if OopWord = 'ENERGIZED' then begin
				OopCheckCondition := World.Info.EnergizerTicks > 0;
			end else if OopWord = 'ANY' then begin
				if not OopParseTile(statId, position, tile) then
					OopError(statId, 'Bad object kind');

				ix := 0;
				iy := 1;
				OopCheckCondition := FindTileOnBoard(ix, iy, tile);
			{#IF X[=|<|>]<number>}
			end else if OopWord = 'X' then begin
				OopReadChar(statId, position);
				operation := OopChar;
				OopReadValue(statId, position);
				if operation = '>' then
					OopCheckCondition := (Board.Stats[statId].X > OopValue)
				else if operation = '<' then
					OopCheckCondition := (Board.Stats[statId].X < OopValue)
				else {=}
					OopCheckCondition := (Board.Stats[statId].X = OopValue);
			{#IF Y[=|<|>]<number>}
			end else if OopWord = 'Y' then begin
				OopReadChar(statId, position);
				operation := OopChar;
				OopReadValue(statId, position);
				if operation = '>' then
					OopCheckCondition := (Board.Stats[statId].Y > OopValue)
				else if operation = '<' then
					OopCheckCondition := (Board.Stats[statId].Y < OopValue)
				else {=}
					OopCheckCondition := (Board.Stats[statId].Y = OopValue);
			{#IF READ <filename>[=|<|>]<number|string>}
			end else if OopWord = 'READ' then begin
				OopReadWord(statId, position);
				OopReadFile(OopWord, FileContents);
				OopReadChar(statId, position);
				operation := OopChar;
				OopReadValue(statId, position);
				Val(FileContents, num, code);
				if (code = 0) and (OopValue <> -1) then begin
					if operation = '>' then
						OopCheckCondition := (num > OopValue)
					else if operation = '<' then
						OopCheckCondition := (num < OopValue)
					else {=}
						OopCheckCondition := (num = OopValue);
				end else begin
					OopReadWord(statId, position);
					OopCheckCondition := (UpCase(FileContents) = OopWord);
				end;
			{#IF VAR <number 1-MAX_FLAG>[=|<|>]<number|string>}
			end else if OopWord = 'VAR' then begin
				OopReadValue(statId, position);
				iVar := OopValue;
				if ZVars[iVar] <> '' then begin
					Val(ZVars[iVar], num, code);
					OopReadChar(statId, position);
					operation := OopChar;
					OopReadValue(statId, position);
					if (code = 0) and (OopValue <> -1) then begin
						if operation = '>' then
							OopCheckCondition := (num > OopValue)
						else if operation = '<' then
							OopCheckCondition := (num < OopValue)
						else {=}
							OopCheckCondition := (num = OopValue);
					end else begin
						OopReadWord(statId, position);
						OopCheckCondition := (UpCase(ZVars[iVar]) = OopWord);
					end;
				end else
					OopSkipLine(statId, position);
			{END}
			end else begin
				OopCheckCondition := WorldGetFlagPosition(OopWord) >= 0;
			end;
		end;
	end;

function OopReadLineToEnd(statId: integer; var position: integer) : string;
	var
		s: string;
		sPos: byte;
	begin
		sPos := 0;
		OopReadChar(statId, position);
		while (OopChar <> #0) and (OopChar <> #13) do begin
			if sPos < 255 then begin
				Inc(sPos);
				s[sPos] := OopChar;
			end;
			OopReadChar(statId, position);
		end;
		s[0] := Chr(sPos);
		OopReadLineToEnd := s;
	end;

function OopSend(statId: integer; sendLabel: string; ignoreLock: boolean): boolean;
	var
		iDataPos, iStat: integer;
		respectSelfLock: boolean;
	begin
		{ If the statId passed is positive, the passed stat will always }
		{ receive the label irrespective of whether it has been locked }
		{ or not. ZZT uses positive stat IDs for labels sent by objects, }
		{ and negative stat IDs for labels sent by in-world events (like }
		{ touch, shot or energize). }
		if statId < 0 then begin
			statId := -statId;
			respectSelfLock := true;
		end else begin
			respectSelfLock := false;
		end;

		OopSend := false;
		iStat := 0;

		while OopFindLabel(statId, sendLabel, iStat, iDataPos, #13':') do begin
			if ((Board.Stats[iStat].P2 = 0) or ignoreLock) or ((statId = iStat) and not respectSelfLock) then begin
				if iStat = statId then
					OopSend := true;

				Board.Stats[iStat].DataPos := iDataPos;
			end;
		end;
	end;

procedure OopExecute(statId: integer; var position: integer; name: TString50);
	var
		textWindow: TTextWindowState;
		textLine: string;
		deltaX, deltaY: integer;
		ix, iy: integer;
		stopRunning: boolean;
		replaceStat: boolean;
		endOfProgram: boolean;
		replaceTile: TTile;
		namePosition: integer;
		lastPosition: integer;
		repeatInsNextTick: boolean;
		lineFinished: boolean;
		labelPtr: pointer;
		labelDataPos: integer;
		labelStatId: integer;
		counterPtr: ^integer;
		counterSubtract: boolean;
		bindStatId: integer;
		insCount: integer;
		argTile: TTile;
		argTile2: TTile;
		fxArgs: array[0 .. 3] of byte;
		f: byte;
		fxDmg: boolean;
		iStat: integer;
		iVar: integer;
		num: integer;
		code: integer;
		operation: char;
		{newStat: TStat;}
		{iPos: integer;}
	label StartParsing;
	label ReadInstruction;
	label ReadCommand;
	begin
		with Board.Stats[statId] do begin
		StartParsing:
			TextWindowInitState(textWindow);
			textWindow.Selectable := false;
			stopRunning := false;
			repeatInsNextTick := false;
			replaceStat := false;
			endOfProgram := false;
			insCount := 0;
			repeat
		ReadInstruction:
				lineFinished := true;
				lastPosition := position;
				OopReadChar(statId, position);

				{ skip labels }
				while OopChar = ':' do begin
					repeat
						OopReadChar(statId, position);
					until (OopChar = #0) or (OopChar = #13);
					OopReadChar(statId, position);
				end;

				if OopChar = #39 { apostrophe } then begin
					OopSkipLine(statId, position);
				end else if OopChar = '@' then begin
					OopSkipLine(statId, position);
				end else if (OopChar = '/') or (OopChar = '?') then begin
					if OopChar = '/' then
						repeatInsNextTick := true;

					OopReadWord(statId, position);
					if OopParseDirection(statId, position, deltaX, deltaY) then begin
						if (deltaX <> 0) or (deltaY <> 0) then begin
							if not ElementDefs[Board.Tiles[X + deltaX][Y + deltaY].Element].Walkable then
								ElementPushablePush(X + deltaX, Y + deltaY, deltaX, deltaY);

							if ElementDefs[Board.Tiles[X + deltaX][Y + deltaY].Element].Walkable then begin
								MoveStat(statId, X + deltaX, Y + deltaY);
								repeatInsNextTick := false;
							end;
						end else begin
							repeatInsNextTick := false;
						end;

						OopReadChar(statId, position);
						if OopChar <> #13 then
							Dec(position);

						stopRunning := true;
					end else begin
						OopError(statId, 'Bad direction');
					end;
				end else if OopChar = '#' then begin
		ReadCommand:
					OopReadWord(statId, position);
					if OopWord = 'THEN' then
						OopReadWord(statId, position);
					if Length(OopWord) = 0 then
						goto ReadInstruction;
					Inc(insCount);
					{ if Length(OopWord) <> 0 then begin // already checked above }
						if OopWord = 'GO' then begin
							OopReadDirection(statId, position, deltaX, deltaY);

							if not ElementDefs[Board.Tiles[X + deltaX][Y + deltaY].Element].Walkable then
								ElementPushablePush(X + deltaX, Y + deltaY, deltaX, deltaY);

							if ElementDefs[Board.Tiles[X + deltaX][Y + deltaY].Element].Walkable then begin
								MoveStat(statId, X + deltaX, Y + deltaY);
							end else begin
								repeatInsNextTick := true;
							end;

							stopRunning := true;
						end else if OopWord = 'TRY' then begin
							OopReadDirection(statId, position, deltaX, deltaY);

							if not ElementDefs[Board.Tiles[X + deltaX][Y + deltaY].Element].Walkable then
								ElementPushablePush(X + deltaX, Y + deltaY, deltaX, deltaY);

							if ElementDefs[Board.Tiles[X + deltaX][Y + deltaY].Element].Walkable then begin
								MoveStat(statId, X + deltaX, Y + deltaY);
								stopRunning := true;
							end else begin
								goto ReadCommand;
							end;
						end else if OopWord = 'WALK' then begin
							OopReadDirection(statId, position, deltaX, deltaY);
							StepX := deltaX;
							StepY := deltaY;
						end else if OopWord = 'SET' then begin
							OopReadWord(statId, position);
							WorldSetFlag(OopWord);
						end else if OopWord = 'CLEAR' then begin
							OopReadWord(statId, position);
							WorldClearFlag(OopWord);
						end else if OopWord = 'IF' then begin
							OopReadWord(statId, position);
							if OopCheckCondition(statId, position) then
								goto ReadCommand;
						end else if OopWord = 'SHOOT' then begin
							OopReadDirection(statId, position, deltaX, deltaY);
							if BoardShoot(E_BULLET, X, Y, deltaX, deltaY, SHOT_SOURCE_ENEMY) then
								SoundQueue(2, #48#1#38#1);
							stopRunning := true;
						end else if OopWord = 'THROWSTAR' then begin
							OopReadDirection(statId, position, deltaX, deltaY);
							if BoardShoot(E_STAR, X, Y, deltaX, deltaY, SHOT_SOURCE_ENEMY) then
								begin end;
							stopRunning := true;
						end else if (OopWord = 'GIVE') or (OopWord = 'TAKE') then begin
							if OopWord = 'TAKE' then
								counterSubtract := true
							else
								counterSubtract := false;

							OopReadWord(statId, position);
							if OopWord = 'HEALTH' then
								counterPtr := @World.Info.Health
							else if OopWord = 'AMMO' then
								counterPtr := @World.Info.Ammo
							else if OopWord = 'GEMS' then
								counterPtr := @World.Info.Gems
							else if OopWord = 'TORCHES' then
								counterPtr := @World.Info.Torches
							else if OopWord = 'SCORE' then
								counterPtr := @World.Info.Score
							else if OopWord = 'TIME' then
								counterPtr := @World.Info.BoardTimeSec
							else
								counterPtr := nil;

							if counterPtr <> nil then begin
								OopReadValue(statId, position);
								if OopValue > 0 then begin
									if counterSubtract then
										OopValue := -OopValue;

									if (counterPtr^ + OopValue) >= 0 then begin
										Inc(counterPtr^, OopValue);
									end else begin
										goto ReadCommand;
									end;
								end;
							end;

							GameUpdateSidebar;
						end else if OopWord = 'END' then begin
							position := -1;
							OopChar := #0;
						end else if OopWord = 'ENDGAME' then begin
							World.Info.Health := 0;
						end else if OopWord = 'IDLE' then begin
							stopRunning := true;
						end else if OopWord = 'RESTART' then begin
							position := 0;
							lineFinished := false;
						end else if OopWord = 'ZAP' then begin
							OopReadWord(statId, position);

							labelStatId := 0;
							while OopFindLabel(statId, OopWord, labelStatId, labelDataPos, #13':') do begin
								labelPtr := Board.Stats[labelStatId].Data;
								AdvancePointer(labelPtr, labelDataPos + 1);

								Char(labelPtr^) := #39;
							end;
						end else if OopWord = 'RESTORE' then begin
							OopReadWord(statId, position);

							labelStatId := 0;
							while OopFindLabel(statId, OopWord, labelStatId, labelDataPos, #13#39) do
								repeat
									labelPtr := Board.Stats[labelStatId].Data;
									AdvancePointer(labelPtr, labelDataPos + 1);

									Char(labelPtr^) := ':';

									labelDataPos := OopFindString(labelStatId, labelDataPos + 1, #13#39 + OopWord + #13);
								until labelDataPos <= 0;
						end else if OopWord = 'LOCK' then begin
							P2 := 1;
						end else if OopWord = 'UNLOCK' then begin
							P2 := 0;
						end else if OopWord = 'SEND' then begin
							OopReadWord(statId, position);
							if OopSend(statId, OopWord, false) then
								lineFinished := false;
						end else if OopWord = 'BECOME' then begin
							if OopParseTile(statId, position, argTile) then begin
								replaceStat := true;
								replaceTile := argTile;
							end else begin
								OopError(statId, 'Bad #BECOME');
							end;
						end else if OopWord = 'PUT' then begin
							OopReadDirection(statId, position, deltaX, deltaY);
							if (deltaX = 0) and (deltaY = 0) then
								OopError(statId, 'Bad #PUT')
							else if not OopParseTile(statId, position, argTile) then
								OopError(statId, 'Bad #PUT')
							else if ((X + deltaX) > 0)
								and ((X + deltaX) <= BOARD_WIDTH)
								and ((Y + deltaY) > 0)
								and ((Y + deltaY) < BOARD_HEIGHT) then
							begin
								if not ElementDefs[Board.Tiles[X + deltaX][Y + deltaY].Element].Walkable then
									ElementPushablePush(X + deltaX, Y + deltaY, deltaX, deltaY);

								OopPlaceTile(X + deltaX, Y + deltaY, argTile);
							end;
						end else if OopWord = 'CHANGE' then begin
							if not OopParseTile(statId, position, argTile) then
								OopError(statId, 'Bad #CHANGE');
							if not OopParseTile(statId, position, argTile2) then
								OopError(statId, 'Bad #CHANGE');

							ix := 0;
							iy := 1;
							if (argTile2.Color = 0)
								and (ElementDefs[argTile2.Element].Color < COLOR_SPECIAL_MIN)
							then
								argTile2.Color := ElementDefs[argTile2.Element].Color;

							while FindTileOnBoard(ix, iy, argTile) do
								OopPlaceTile(ix, iy, argTile2);
						end else if OopWord = 'PLAY' then begin
							textLine := SoundParse(OopReadLineToEnd(statId, position));
							if Length(textLine) <> 0 then
								SoundQueue(-1, textLine);
							lineFinished := false;
						end else if OopWord = 'CYCLE' then begin
							OopReadValue(statId, position);
							if OopValue > 0 then
								Cycle := OopValue;
						end else if OopWord = 'CHAR' then begin
							OopReadValue(statId, position);
							if (OopValue > 0) and (OopValue <= 255) then begin
								P1 := OopValue;
								BoardDrawTile(X, Y);
							end;
							if OopValue = -1 then begin
								OopReadWord(statId, position);
								if OopWord = 'RND' then begin
									P1 := Random(222) + 32;
									BoardDrawTile(X, Y);
								end;
							end;
						end else if OopWord = 'DIE' then begin
							replaceStat := true;
							replaceTile.Element := E_EMPTY;
							replaceTile.Color := $0F;
						end else if OopWord = 'BIND' then begin
							OopReadWord(statId, position);
							bindStatId := 0;
							if OopIterateStat(statId, bindStatId, OopWord) then begin
								if statId <> bindStatId then begin
									FreeStatDataMem(statId, true);
									Data := Board.Stats[bindStatId].Data;
									DataLen := Board.Stats[bindStatId].DataLen;
{$IFDEF DEBUGWND}
								end else if DebugCompatEnabled then begin
									DebugShowElementMessage('Illegal double free (self-#BIND)', X, Y);
{$ENDIF}
								end;
								position := 0;
							end;
						{#BOARD <number>}
						end else if OopWord = 'BOARD' then begin
							OopReadValue(statId, position);
							BoardChange(OopValue);
							TransitionDrawBoardChange;
							BoardEnter;
						{#BULLETS <ON|OFF>}
						end else if OopWord = 'BULLETS' then begin
							OopReadWord(statId, position);
							BulletsOn := (OopWord <> 'OFF');
						{#COLOR <color|$byte>}
						end else if OopWord = 'COLOR' then begin
							if OopParseTile(statId, position, argTile) then begin
								Board.Tiles[X][Y].Color := argTile.Color;
								BoardDrawTile(X, Y);
							end;
						{#CLONE [<object name>] <number x> <number y>} {trying to add clone name change}
						end else if OopWord = 'CLONE' then begin
							OopReadWord(statId, position);
							OopReadValue(statId, position);
							ix := OopValue;
							OopReadValue(statId, position);
							iy := OopValue;
							iStat := 0;
							{newStat := Board.Stats[iStat];}
							if OopWord <> '' then begin
								if not OopIterateStat(statId, iStat, OopWord) then
									OopError(statId, 'Bad #CLONE');
							end else
								iStat := statId;
							{if (ix <> -1) and (iy <> -1) then trying to add direction}
								
							{OopReadWord(statId, position);}
							{if Length(OopWord) <> 0 then begin}
								{if Board.Stats[iStat].Data <> nil then begin}
									{iPos := 0;}
									{OopReadChar(iStat, iPos);}
									{if OopChar = '@' then begin}
										{OopReadLineToEnd(iStat, iPos);}
										{newStat.Data := Copy(Board.Stats[iStat].Data, iPos, Length(Board.Stats[iStat].Data));}
										{newStat.DataLen := Length(newStat.Data);}
									{end;}
								{end;}
							AddStat(ix, iy, Board.Tiles[Board.Stats[iStat].X][Board.Stats[iStat].Y].Element,
								Board.Tiles[Board.Stats[iStat].X][Board.Stats[iStat].Y].Color,
								Board.Stats[iStat].Cycle, Board.Stats[iStat]);
							BoardDrawTile(ix, iy);
						{#FX [DMG] [<number 1|2>] [<number x>] [<number y>] [<number distsqr>] [RED|WHITE]}
						end else if OopWord = 'FX' then begin
							fxDmg := false;
							for f := 0 to 3 do begin
								OopReadValue(statId, position);
								if OopValue > 0 then begin
									fxArgs[f] := OopValue;
								end else begin
									fxArgs[f] := fxDefaults[f];
								end;
							end;
							OopReadWord(statId, position);
							fxDmg := (OopWord = 'DMG');
							if fxDmg then
								OopReadWord(statId, position);
							DrawParticles(X, Y, fxArgs[0], fxDmg, fxArgs[1], fxArgs[2], fxArgs[3], OopWord);
						{#HEALTH <number>}
						end else if OopWord = 'HEALTH' then begin
							OopReadValue(statId, position);
							if OopValue <> -1 then begin
								World.Info.Health := OopValue;
								GameUpdateSidebar;
							end;
						{#SPEED <number (default 8)> [<number 0-90 micro ticks, use when initial #SPEED set to 0>]}
						end else if OopWord = 'SPEED' then begin
							OopReadValue(statId, position);
							TickTimeDuration := OopValue;
							if OopValue = 0 then begin
								OopReadValue(statId, position);
								MicroSpeed := OopValue;
							end;
						{#TIMER <number 0-127 ticks> [SHOW]}
						end else if OopWord = 'TIMER' then begin
							OopReadValue(statId, position);
							OopReadWord(statId, position);
							if OopWord = 'SHOW' then
								P3 := OopValue
							else
								P3 := OopValue + $80;
							if OopValue = 0 then
								BoardDrawTile(X, Y);
						{#READ alias of #IF READ}
						end else if OopWord= 'READ' then begin
							if OopCheckCondition(statId, position) then
								goto ReadCommand;
						{#WRITE <filename> <number|string>}
						end else if OopWord = 'WRITE' then begin
							OopReadWord(statId, position);
							Inc(position);
							{zFile.LineCount := 1;}
							{New(zFile.Lines[1]);}
							{zFile.Lines[1]^ := OopReadLineToEnd(statId, position);}
							{TextWindowSaveFile(OopWord, zFile);}
							OopMakeFile(OopWord, OopReadLineToEnd(statId, position));
						{#SONG [LOOP|STOP] <filename>}
						end else if OopWord = 'SONG' then begin
							LoopSong := false;
							OopReadWord(statId, position);
							if OopWord = 'STOP' then
								SoundClearQueue
							else begin
								if OopWord = 'LOOP' then begin
									LoopSong := true;
									OopReadWord(statId, position);
								end;
								SoundOpenFile(OopWord, LoadedSong);
								if LoadedSong.LineCount <> 0 then
									SongIsPlaying := true;
							end;
						{#VAR <number 1-MAX_FLAG> <number|string>}
						end else if OopWord = 'VAR' then begin
							OopReadValue(statId, position);
							iVar := OopValue;
							OopReadChar(statId, position);
							operation := OopChar;
							if ((operation = '-') or (operation = '+')) and (ZVars[iVar] <> '') then begin
								OopReadValue(statId, position);
								if OopValue = -1 then
									OopValue := 1;
								if operation = '-' then
									OopValue := -OopValue;
								Val(ZVars[iVar], num, code);
								Str(num + OopValue, ZVars[iVar]);
							end else
								ZVars[iVar] := OopReadLineToEnd(statId, position);
							{position := position + 1;}
						{ZENON END}
						end else begin
							textLine := OopWord;
							if OopSend(statId, OopWord, false) then begin
								lineFinished := false;
							end else begin
								if Pos(':', textLine) <= 0 then begin
									OopError(statId, 'Bad command ' + textLine);
								end;
							end;
						end;
					{ end; }

					if lineFinished then
						OopSkipLine(statId, position);
				end else if OopChar = #13 then begin
					if textWindow.LineCount > 0 then
						TextWindowAppend(textWindow, '');
				end else if OopChar = #0 then begin
					endOfProgram := true;
				end else begin
					textLine := OopChar + OopReadLineToEnd(statId, position);
					TextWindowAppend(textWindow, textLine);
				end;
			until endOfProgram or stopRunning or repeatInsNextTick or replaceStat or (insCount > 32);

			if repeatInsNextTick then
				position := lastPosition;

			if OopChar = #0 then
				position := -1;

			if textWindow.LineCount > 1 then begin
				namePosition := 0;
				OopReadChar(statId, namePosition);
				if OopChar = '@' then begin
					name := OopReadLineToEnd(statId, namePosition);
				end;

				if Length(name) = 0 then
					name := 'Interaction';

				textWindow.Title := name;
				TextWindowDrawOpen(textWindow);
				TextWindowSelect(textWindow, TWS_HYPERLINK_AS_SELECT);
				TextWindowDrawClose(textWindow);
				TextWindowFree(textWindow);

				if Length(textWindow.Hyperlink) <> 0 then
					if OopSend(statId, textWindow.Hyperlink, false) then
						goto StartParsing;
			end else if textWindow.LineCount = 1 then begin
				DisplayMessage(200, textWindow.Lines[1]^);
				TextWindowFree(textWindow);
			end;

			if replaceStat then begin
				ix := X;
				iy := Y;
				DamageStat(statId);
				OopPlaceTile(ix, iy, replaceTile);
			end;
		end;
	end;

end.
