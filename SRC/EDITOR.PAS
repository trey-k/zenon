{	Copyright (c) 2020 Adrian Siekierka

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
unit Editor;

interface
	uses GameVars, TxtWind;
{$IFDEF EDITOR}
	procedure EditorLoop;
{$ENDIF}
	procedure HighScoresLoad;
	procedure HighScoresSave;
	procedure HighScoresDisplay(linePos: integer);
{$IFDEF EDITOR}
	procedure EditorOpenEditTextWindow(var state: TTextWindowState; extension: TExtensionString;
		syntaxHighlighting: boolean);
	procedure EditorEditTextFile;
{$ENDIF}
	procedure HighScoresAdd(score: integer);
	function EditorGetBoardName(boardId: integer; titleScreenIsNone: boolean): TString50;
	function EditorSelectBoard(title: string; currentBoard: integer; titleScreenIsNone: boolean;
		windowAlreadyOpen: boolean): integer;

implementation
uses Dos, FileSel, ExtMem, ZVideo, Sounds, Input, Elements, Oop, Game;

type
	TDrawMode = (DrawingOff, DrawingOn, TextEntry);
	TEditorCopiedTile = record
		stat: TStat;
		hasStat: boolean;
		tile: TTile;
		previewChar: byte;
		previewColor: byte;
	end;
	TEditorCopyTileBuffer = array[0 .. 32000] of TTile;
	TEditorCopyStatBuffer = array[1 .. MAX_STAT + 2] of TStat;
	TEditorCopyBuffer = record
		tiles: ^TEditorCopyTileBuffer;
		stats: ^TEditorCopyStatBuffer;
		statCount: integer;
		width: byte;
		height: byte;
	end;

const
	COPIED_TILES_COUNT = 10;
	NeighborBoardStrs: array[0 .. 3] of string[20] =
		('       Board '#24, '       Board '#25, '       Board '#27, '       Board '#26);
{	ColorNames: array[0 .. 15] of string[7] =
		('Black  ', 'DBlue  ', 'DGreen ', 'DCyan  ', 'DRed   ', 'DPurple', 'Brown  ', 'LGray  ',
		'DGray  ', 'Blue   ', 'Green  ', 'Cyan   ', 'Red    ', 'Purple ', 'Yellow ', 'White  ');}
	ColorNames: array[0 .. 15] of string[3] =
		('Blk', 'DBl', 'DGn', 'DCy', 'DRe', 'DMa', 'Bro', 'LGr', 'DGr', 'LBl', 'LGn', 'LCy', 'LRe', 'LMa', 'Yel', 'Wht');

procedure EditorAppendBoard;
	begin
		if World.BoardCount < MAX_BOARD then begin
			BoardClose;

			Inc(World.BoardCount);
			World.Info.CurrentBoard := World.BoardCount;
			World.BoardLen[World.BoardCount] := 0;
			BoardCreate;

			TransitionDrawToBoard;

			repeat
				PopupPromptString('Room'#39's Title:', Board.Name, MAX_BOARD_NAME_LENGTH);
			until Length(Board.Name) <> 0;

			TransitionDrawToBoard;
		end;
	end;

{$IFDEF EDITOR}
procedure EditorCopyStat(var fromStat: TStat; var toStat: TStat);
	begin
		Move(fromStat, toStat, SizeOf(TStat));
		if toStat.DataLen > 0 then begin
			GetMem(toStat.Data, toStat.DataLen);
			Move(fromStat.Data^, toStat.Data^, toStat.DataLen);
		end else begin
			toStat.DataLen := 0;
		end;
	end;

procedure EditorWorldCanOpenCheck(closeSavesSilently: boolean);
	var
		isSecret: boolean;
	begin
		{ Secret worlds: warn always }
		{ Savegames: error if non-debug, warn if debug }
		isSecret := (WorldGetFlagPosition('SECRET') >= 0);
		if (World.Info.IsSave and (not closeSavesSilently)) or isSecret then begin
			SidebarClearLine(3);
			SidebarClearLine(4);
			SidebarClearLine(5);
			VideoWriteText(63, 4, $1E, 'World marked as');
			if World.Info.IsSave then
				VideoWriteText(63, 5, $1E, ' a saved game!')
			else
				VideoWriteText(63, 5, $1E, '    locked!');
			PauseOnError;
		end;
		if World.Info.IsSave and (not DebugEnabled) then begin
			WorldUnload;
			WorldCreate;
		end;
	end;

procedure EditorLoop;
	var
		selectedCategory: integer;
		elemMenuColor: integer;
		wasModified: boolean;
		editorExitRequested: boolean;
		drawMode: TDrawMode;
		cursorX, cursorY: integer;
		cursorPattern, cursorColor: integer;
		colorIgnoreDefaults: boolean;
		i, iElem: integer;
		canModify: boolean;
		copiedTiles: array[1 .. COPIED_TILES_COUNT] of TEditorCopiedTile;
		cursorBlinker: integer;
		inputByte: byte;
		copyBuffer: TEditorCopyBuffer;

	function EditorGetDrawingColor(eid: integer): integer;
		begin
			if eid = E_PLAYER then
				EditorGetDrawingColor := ElementDefs[eid].Color
			else if colorIgnoreDefaults or (ElementDefs[eid].Color = COLOR_CHOICE_ON_BLACK) then
				EditorGetDrawingColor := cursorColor
			else if ElementDefs[eid].Color = COLOR_WHITE_ON_CHOICE then
				EditorGetDrawingColor := ((cursorColor and $07) shl 4) + $0F
			else if ElementDefs[eid].Color = COLOR_CHOICE_ON_CHOICE then
				EditorGetDrawingColor := ((cursorColor and $07) * $11) + 8
			else
				EditorGetDrawingColor := ElementDefs[eid].Color;
		end;

	procedure EditorUpdateCursorColor;
		var
			colorBg, colorFg: byte;
		begin
			VideoWriteText(72, 19, $1E, ColorNames[cursorColor and $0F]);
			VideoWriteText(76, 19, $1E, ColorNames[cursorColor shr 4]);

			VideoWriteText(61, 24, $1F, '                ');

			colorBg := cursorColor shr 4;
			colorFg := cursorColor and $0F;

			if colorBg = colorFg then begin
				VideoWriteText(61 + colorBg, 24, $9F, #30);
			end else begin
				VideoWriteText(61 + colorFg, 24, $1F, #24);
				VideoWriteText(61 + colorBg, 24, $1F, '^');
			end;
		end;

	procedure EditorUpdateCursorPattern;
		begin
			VideoWriteText(61, 22, $1F, '                ');
			VideoWriteText(60 + cursorPattern, 22, $1F, #30);
		end;

	procedure EditorUpdateDrawMode;
		begin
			case drawMode of
				DrawingOn: VideoWriteText(75, 16, $9E, 'Draw');
				TextEntry: VideoWriteText(75, 16, $9E, 'Text');
				DrawingOff: VideoWriteText(75, 16, $1E, 'None');
			end;

			if drawMode = TextEntry then begin
				VideoWriteText(61, 15, $70, '  f10  ');
				VideoWriteText(68, 15, $1F, ' Custom');
			end else begin
				VideoWriteText(61, 15, $70, ' Space ');
				VideoWriteText(68, 15, $1F, ' Plot  ');
			end;
		end;

	procedure EditorUpdateColorIgnoreDefaults;
		begin
			if colorIgnoreDefaults then
				VideoWriteText(78, 23, $1F, 'd')
			else
				VideoWriteText(78, 23, $1F, 'D')
		end;

	procedure EditorUpdateCopiedPatterns;
		var
			i: integer;
		begin
			for i := 1 to COPIED_TILES_COUNT do
				with copiedTiles[i] do
					VideoWriteText(60 + EditorPatternCount + i, 21, previewColor, Chr(previewChar));
		end;

	procedure EditorClearPattern(var copied: TEditorCopiedTile; first: boolean);
		begin
			with copied do begin
				hasStat := false;
				tile.Element := 0;
				tile.Color := $0F;
				previewChar := 0;
				previewColor := $0F;
				if first then stat.Data := nil
				else if stat.Data <> nil then FreeMem(stat.Data, stat.DataLen);
			end;
		end;

	{ TODO: Unify with BoardDrawTile? }
	procedure EditorCopyPattern(x, y: integer; var copied: TEditorCopiedTile);
		var
			statId: integer;
		begin
			if Board.Tiles[cursorX][cursorY].Element = E_PLAYER then
				exit;

			statId := GetStatIdAt(x, y);

			EditorClearPattern(copied, false);
			with copied do begin
				tile := Board.Tiles[cursorX][cursorY];
				hasStat := statId > 0;
				if hasStat then
					EditorCopyStat(Board.Stats[statId], stat);
				if ElementDefs[tile.Element].HasDrawProc then
					ElementDefs[tile.Element].DrawProc(x, y, previewChar)
				else if tile.Element < E_TEXT_MIN then
					previewChar := Ord(ElementDefs[tile.Element].Character)
				else
					previewChar := tile.Color;

				if tile.Element < E_TEXT_MIN then
					previewColor := tile.Color
				else if tile.Element = E_TEXT_WHITE then
					previewColor := $0F
				else
					previewColor := (((tile.Element - E_TEXT_MIN) + 1) shl 4) + $0F;
			end;
		end;

	procedure EditorCopyPatternToCurrent(x, y: integer);
		begin
			if cursorPattern > EditorPatternCount then
				EditorCopyPattern(x, y, copiedTiles[cursorPattern - EditorPatternCount]);
		end;

	procedure EditorDrawSidebar;
		var
			i: integer;
			copiedChr: byte;
		begin
			SidebarClear;
			SidebarClearLine(1);
			VideoWriteText(61, 0, $1F, '     - - - -       ');
			VideoWriteText(62, 1, $70, '  ZZT* Editor  ');
			VideoWriteText(61, 2, $1F, '     - - - -       ');
			VideoWriteText(61, 4, $70, ' L ');
			VideoWriteText(64, 4, $1F, ' Load');
			VideoWriteText(61, 5, $30, ' S ');
			VideoWriteText(64, 5, $1F, ' Save');
			VideoWriteText(70, 4, $70, ' H ');
			VideoWriteText(73, 4, $1F, ' Help');
			VideoWriteText(70, 5, $30, ' Q ');
			VideoWriteText(73, 5, $1F, ' Quit');
			VideoWriteText(61, 7, $70, ' B ');
			VideoWriteText(64, 7, $1F, ' Switch boards');
			VideoWriteText(61, 8, $30, ' I ');
			VideoWriteText(64, 8, $1F, ' Board Info');
			VideoWriteText(61, 10, $70, '  f1   ');
			VideoWriteText(68, 10, $1F, ' Item');
			VideoWriteText(61, 11, $30, '  f2   ');
			VideoWriteText(68, 11, $1F, ' Creature');
			VideoWriteText(61, 12, $70, '  f3   ');
			VideoWriteText(68, 12, $1F, ' Terrain');
			VideoWriteText(61, 13, $30, '  f4   ');
			VideoWriteText(68, 13, $1F, ' Enter text');
			VideoWriteText(61, 16, $30, '  Tab  ');
			VideoWriteText(68, 16, $1F, ' Mode:');
			VideoWriteText(61, 18, $70, ' P ');
			VideoWriteText(64, 18, $1F, ' Pattern');
			VideoWriteText(61, 19, $30, ' C ');
			VideoWriteText(64, 19, $1F, ' Color:');
			VideoWriteText(75, 19, $1F, #26);

			{ Colors }
			for i := 0 to 15 do
				VideoWriteText(61 + i, 23, $10 + i, #219);
			EditorUpdateCursorColor;
			EditorUpdateColorIgnoreDefaults;

			{ Patterns }
			for i := 1 to EditorPatternCount do
				VideoWriteText(60 + i, 21, $0F, ElementDefs[EditorPatterns[i]].Character);
			EditorUpdateCopiedPatterns;
			EditorUpdateCursorPattern;

			EditorUpdateDrawMode;
		end;

	procedure EditorDrawTileAndNeighborsAt(x, y: integer);
		var
			i, ix, iy: integer;
		begin
			BoardDrawTile(x, y);
			for i := 0 to 3 do begin
				ix := x + NeighborDeltaX[i];
				iy := y + NeighborDeltaY[i];
				if (ix >= 1) and (ix <= BOARD_WIDTH) and (iy >= 1) and (iy <= BOARD_HEIGHT) then
					BoardDrawTile(ix, iy);
			end;
		end;

	procedure EditorDrawRefresh;
		var
			boardNumStr: string;
		begin
			BoardDrawBorder;
			EditorDrawSidebar;
			Str(World.Info.CurrentBoard, boardNumStr);
			TransitionDrawToBoard;

			if Length(Board.Name) <> 0 then
				VideoWriteText((59 - Length(Board.Name)) div 2, 0, $70, ' ' + Board.Name + ' ')
			else
				VideoWriteText(26, 0, $70, ' Untitled ');
		end;

	procedure EditorSetTile(x, y, newElement, newColor: byte);
		begin
			with Board.Tiles[x][y] do begin
				Element := newElement;
				Color := newColor;
			end;
			EditorDrawTileAndNeighborsAt(x, y);
		end;

	procedure EditorSetAndCopyTile(x, y, element, color: byte);
		begin
			EditorSetTile(x, y, element, color);

			EditorCopyPatternToCurrent(x, y);
			EditorUpdateCopiedPatterns;
		end;

	procedure EditorAskSaveChanged;
		begin
			InputKeyPressed := #0;
			if wasModified then
				if SidebarPromptYesNo('Save first? ', true) then
					if InputKeyPressed <> KEY_ESCAPE then
						GameWorldSave('Save world', LoadedGameFileName, '.ZZT');
			World.Info.Name := LoadedGameFileName;
		end;

	function EditorPrepareModifyTile(x, y: integer): boolean;
		begin
			wasModified := true;
			EditorPrepareModifyTile := BoardPrepareTileForPlacement(x, y);
			EditorDrawTileAndNeighborsAt(x, y);
		end;

	function EditorPrepareModifyStatAtCursor: boolean;
		begin
			if Board.StatCount < MAX_STAT then
				EditorPrepareModifyStatAtCursor := EditorPrepareModifyTile(cursorX, cursorY)
			else
				EditorPrepareModifyStatAtCursor := false;
		end;

	procedure EditorPlaceTile(x, y: integer);
		begin
			with Board.Tiles[x][y] do begin
				if cursorPattern <= EditorPatternCount then begin
					if EditorPrepareModifyTile(x, y) then begin
						Element := EditorPatterns[cursorPattern];
						Color := cursorColor;
					end;
				end else with copiedTiles[cursorPattern - EditorPatternCount] do begin
					if hasStat then begin
						if EditorPrepareModifyStatAtCursor then begin
							AddStat(x, y, tile.Element, tile.Color, stat.Cycle, stat);
						end
					end else begin
						if EditorPrepareModifyTile(x, y) then begin
							Board.Tiles[x][y] := tile;
						end;
					end;
				end;

				EditorDrawTileAndNeighborsAt(x, y);
			end;
		end;

	procedure EditorRemoveTile(x, y: integer);
		var
			statId: integer;
		begin
			statId := GetStatIdAt(x, y);
			if statId > 0 then
				RemoveStat(statId)
			else if statId < 0 then
				Board.Tiles[x][y].Element := E_EMPTY
			else exit; { statId = 0 (player) cannot be modified }
			BoardDrawTile(x, y);
		end;

	procedure EditorEditBoardInfo;
		var
			state: TTextWindowState;
			i: integer;
			numStr: TString50;
			exitRequested: boolean;

		function BoolToString(val: boolean): string;
			begin
				if val then
					BoolToString := 'Yes'
				else
					BoolToString := 'No ';
			end;

		begin
			state.Title := 'Board Information';
			TextWindowDrawOpen(state);
			state.LinePos := 1;
			exitRequested := false;

			repeat
				state.Selectable := true;
				state.LineCount := 10;
				for i := 1 to state.LineCount do
					New(state.Lines[i]);

				state.Lines[1]^ := '         Title: ' + Board.Name;

				Str(Board.Info.MaxShots, numStr);
				state.Lines[2]^ := '      Can fire: ' + numStr + ' shots.';

				state.Lines[3]^ := ' Board is dark: ' + BoolToString(Board.Info.IsDark);

				for i := 4 to 7 do begin
					state.Lines[i]^ := NeighborBoardStrs[i - 4] + ': ' +
						EditorGetBoardName(Board.Info.NeighborBoards[i - 4], true);
				end;

				state.Lines[8]^ := 'Re-enter when zapped: ' + BoolToString(Board.Info.ReenterWhenZapped);

				Str(Board.Info.TimeLimitSec, numStr);
				state.Lines[9]^ := '  Time limit, 0=None: ' + numStr + ' sec.';

				state.Lines[10]^ := '          Quit!';

				TextWindowSelect(state, 0);
				if (InputKeyPressed = KEY_ENTER) and (state.LinePos <> 10) then begin
					wasModified := true;
					case state.LinePos of
						1: begin
							PopupPromptString('New title for board:', Board.Name, MAX_BOARD_NAME_LENGTH);
							exitRequested := true;
							TextWindowDrawClose(state);
						end;
						2: begin
							Str(Board.Info.MaxShots, numStr);
							SidebarPromptString('Maximum shots?', '', numStr, PROMPT_NUMERIC);
							if Length(numStr) <> 0 then
								Val(numStr, Board.Info.MaxShots, i);
							EditorDrawSidebar;
						end;
						3: begin
							Board.Info.IsDark := not Board.Info.IsDark;
						end;
						4, 5, 6, 7: begin
							Board.Info.NeighborBoards[state.LinePos - 4]
								:= EditorSelectBoard(
									NeighborBoardStrs[state.LinePos - 4],
									Board.Info.NeighborBoards[state.LinePos - 4],
									true, true
								);
							if Board.Info.NeighborBoards[state.LinePos - 4] > World.BoardCount then begin
								EditorAppendBoard;
								exitRequested := true;
							end;
						end;
						8: begin
							Board.Info.ReenterWhenZapped := not Board.Info.ReenterWhenZapped;
						end;
						9: begin
							Str(Board.Info.TimeLimitSec, numStr);
							SidebarPromptString('Time limit?', ' Sec', numStr, PROMPT_NUMERIC);
							if Length(numStr) <> 0 then
								Val(numStr, Board.Info.TimeLimitSec, i);
							EditorDrawSidebar;
						end;
					end
				end else begin
					exitRequested := true;
					TextWindowDrawClose(state);
				end;

				TextWindowFree(state);
			until exitRequested;
		end;

	procedure EditorEditStatText(statId: integer; prompt: string);
		var
			state: TTextWindowState;
			i, iLine, iChar, iStat: integer;
			affectedStats: array[0 .. MAX_STAT + 1] of boolean;
		begin
			with Board.Stats[statId] do begin
				state.Title := prompt;
				TextWindowDrawOpen(state);
				state.Selectable := false;
				CopyStatDataToTextWindow(statId, state);

				if DataLen > 0 then begin
					{ Mark every other object that uses our data so that
					  we can update its DataLen afterwards. }
					for iStat := 0 to Board.StatCount do
						affectedStats[iStat] := (Board.Stats[iStat].Data = Data);
					FreeMem(Data, DataLen);
					DataLen := 0;
				end else begin
					{ No other stats are affected. }
					FillChar(affectedStats, Board.StatCount + 1, false);
				end;

				EditorOpenEditTextWindow(state, '.TXT', true);

				for iLine := 1 to state.LineCount do
					Inc(DataLen, Length(state.Lines[iLine]^) + 1);

				if DataLen > 0 then begin
					GetMem(Data, DataLen);
				end;

				{ Update every bound object to have our possibly new pointer
					and new DataLen. }
				for iStat := 0 to Board.StatCount do
					if (iStat <> statId) and affectedStats[iStat] then begin
						Board.Stats[iStat].Data := Data;
						Board.Stats[iStat].DataLen := DataLen;
					end;

				i := 0;
				for iLine := 1 to state.LineCount do begin
					for iChar := 1 to Length(state.Lines[iLine]^) do begin
						{$IFNDEF FPC}
						{ On Turbo Pascal, the array pointer is actually }
						{ a poiter to a string. }
						Data^[i] := state.Lines[iLine]^[iChar];
						{$ELSE}
						Data[i] := state.Lines[iLine]^[iChar];
						{$ENDIF}
						Inc(i);
					end;


					{$IFNDEF FPC}
					{ On Turbo Pascal, the array pointer is actually }
					{ a poiter to a string. }
					Data^[i] := #13;
					{$ELSE}
					Data[i] := #13;
					{$ENDIF}
					Inc(i);
				end;

				TextWindowDrawClose(state);
				TextWindowFreeEdit(state);
				InputKeyPressed := #0;
			end;
		end;

	procedure EditorEditStat(statId: integer);
		var
			element: byte;
			i: integer;
			categoryName: string;
			selectedBoard: byte;
			iy: integer;
			promptByte: byte;

		procedure EditorEditStatSettings(selected: boolean);
			begin
				with Board.Stats[statId] do begin
					InputKeyPressed := #0;
					iy := 9;

					if Length(ElementDefs[element].Param1Name) <> 0 then begin
						if Length(ElementDefs[element].ParamTextName) = 0 then begin
							SidebarPromptSlider(selected, 63, iy, ElementDefs[element].Param1Name, P1);
						end else begin
							if P1 = 0 then
								P1 := World.EditorStatSettings[element].P1;
							BoardDrawTile(X, Y);
							SidebarPromptCharacter(selected, 63, iy, ElementDefs[element].Param1Name, P1);
							BoardDrawTile(X, Y);
						end;
						if selected then
							World.EditorStatSettings[element].P1 := P1;
						Inc(iy, 4);
					end;

					{ if element = E_OBJECT then begin
						SidebarPromptNumeric(selected, 63, iy, 'Initial cycle?', 1, 420, Cycle);
						Inc(iy, 4);
					end; }

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].ParamTextName) <> 0) then
					begin
						if selected then
							EditorEditStatText(statId, ElementDefs[element].ParamTextName);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].Param2Name) <> 0) then
					begin
						promptByte := (P2 and $7F);
						SidebarPromptSlider(selected, 63, iy, ElementDefs[element].Param2Name, promptByte);
						if selected then begin
							P2 := (P2 and $80) + promptByte;
							World.EditorStatSettings[element].P2 := P2;
						end;
						Inc(iy, 4);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].ParamBulletTypeName) <> 0) then
					begin
						promptByte := P2 shr 7;
						SidebarPromptChoice(selected, iy, ElementDefs[element].ParamBulletTypeName,
							'Bullets Stars', promptByte);
						if selected then begin
							P2 := (P2 and $7F) + (promptByte shl 7);
							World.EditorStatSettings[element].P2 := P2;
						end;
						Inc(iy, 4);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].ParamDirName) <> 0) then
					begin
						SidebarPromptDirection(selected, iy, ElementDefs[element].ParamDirName,
							StepX, StepY);
						if selected then begin
							World.EditorStatSettings[element].StepX := StepX;
							World.EditorStatSettings[element].StepY := StepY;
						end;
						Inc(iy, 4);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].ParamBoardName) <> 0) then
					begin
						if selected then begin
							selectedBoard := EditorSelectBoard(ElementDefs[element].ParamBoardName, P3, true, false);
							if selectedBoard <> 0 then begin
								P3 := selectedBoard;
								World.EditorStatSettings[element].P3 := World.Info.CurrentBoard;
								if P3 > World.BoardCount then begin
									EditorAppendBoard;
									{ TODO: is this still necessary? }
									{ copiedHasStat := false;
									copiedTile.Element := 0;
									copiedTile.Color := $0F; }
								end;
								World.EditorStatSettings[element].P3 := P3;
							end else begin
								InputKeyPressed := KEY_ESCAPE;
							end;
							Inc(iy, 4);
						end else begin
							VideoWriteText(63, iy, $1F, 'Room: ' + Copy(EditorGetBoardName(P3, true), 1, 10));
						end;
					end;
				end;
			end;

		begin
			with Board.Stats[statId] do begin
				SidebarClear;

				element := Board.Tiles[X][Y].Element;
				wasModified := true;

				categoryName := '';
				for i := 0 to element do begin
					if (ElementDefs[i].EditorCategory = ElementDefs[element].EditorCategory)
						and (Length(ElementDefs[i].CategoryName) <> 0) then
					begin
						categoryName := ElementDefs[i].CategoryName;
					end;
				end;

				VideoWriteText(64, 6, $1E, categoryName);
				VideoWriteText(64, 7, $1F, ElementDefs[element].Name);

				EditorEditStatSettings(false);
				EditorEditStatSettings(true);

				if InputKeyPressed <> KEY_ESCAPE then begin
					EditorCopyPatternToCurrent(X, Y);
				end;
			end;
		end;

	procedure EditorTransferBoard;
		var
			i: byte;
			f: file;
			memoryError: boolean;
		label TransferEnd;
		begin
			i := 1;
			memoryError := false;
			SidebarPromptChoice(true, 3, 'Transfer board:', 'Import Export', i);
			if InputKeyPressed <> KEY_ESCAPE then begin
				if i = 0 then begin
					SavedBoardFileName := FileSelect('ZZT Boards', '.BRD', FileBoardCachedLinePos);
					if (InputKeyPressed <> KEY_ESCAPE) and (Length(SavedBoardFileName) <> 0) then begin
						Assign(f, SavedBoardFileName + '.BRD');
						Reset(f, 1);
						if DisplayIOError then begin
							Close(f);
							goto TransferEnd;
						end;

						BoardClose;
						ExtMemFree(World.BoardData[World.Info.CurrentBoard], World.BoardLen[World.Info.CurrentBoard]);
						BlockRead(f, World.BoardLen[World.Info.CurrentBoard], 2);
						if not DisplayIOError then begin
							case EnsureIoTmpBufSize(World.BoardLen[World.Info.CurrentBoard]) of
								2: memoryError := true;
								0, 1: begin
									if ExtMemGet(World.BoardData[World.Info.CurrentBoard],
									World.BoardLen[World.Info.CurrentBoard]) then begin
										BlockRead(f, IoTmpBuf^,
											  World.BoardLen[World.Info.CurrentBoard]);
										ExtMemWrite(World.BoardData[World.Info.CurrentBoard], IoTmpBuf^,
											  World.BoardLen[World.Info.CurrentBoard]);
									end else memoryError := true;
								end;
							end;
						end;

						Close(f);

						if DisplayIOError or memoryError then begin
							{ TODO: Show out of memory error. }
							World.BoardLen[World.Info.CurrentBoard] := 0;
							BoardCreate;
							EditorDrawRefresh;
						end else begin
							BoardOpen(World.Info.CurrentBoard);
							EditorDrawRefresh;
							for i := 0 to 3 do
								Board.Info.NeighborBoards[i] := 0;
						end;
					end;
				end else if i = 1 then begin
					SidebarPromptString('Export board', '.BRD', SavedBoardFileName, PROMPT_ALPHANUM);
					if (InputKeyPressed <> KEY_ESCAPE) and (Length(SavedBoardFileName) <> 0) then begin
						case EnsureIoTmpBufSize(World.BoardLen[World.Info.CurrentBoard]) of
							0, 1: begin
								Assign(f, SavedBoardFileName + '.BRD');
								Rewrite(f, 1);
								if DisplayIOError then begin
									Close(f);
									goto TransferEnd;
								end;

								BoardClose;
								BlockWrite(f, World.BoardLen[World.Info.CurrentBoard], 2);
								ExtMemRead(World.BoardData[World.Info.CurrentBoard], IoTmpBuf^,
									World.BoardLen[World.Info.CurrentBoard]);
								BlockWrite(f, IoTmpBuf^,
									World.BoardLen[World.Info.CurrentBoard]);
								BoardOpen(World.Info.CurrentBoard);

								Close(f);

								if DisplayIOError then begin end;
							end;
							2: begin end; { TODO: Show out of memory error. }
						end;
					end;
				end;
			end;
		TransferEnd:
			EditorDrawSidebar;
		end;

	procedure EditorFreeCopyBuffer;
		var
			i: integer;
		begin
			with copyBuffer do begin
				if width <= 0 then exit;

				FreeMem(tiles, Integer(width) * Integer(height) * SizeOf(TTile));
				width := 0;

				if statCount > 0 then begin
					for i := 1 to statCount do begin
						with stats^[i] do begin
							if Data <> nil then FreeMem(Data, DataLen);
						end;
					end;
					FreeMem(stats, statCount * SizeOf(TStat));
				end;
			end;
		end;

	procedure EditorRefreshCopyBuffer(ox, oy, width, height: integer);
		var
			ix, iy, tx, ty: integer;
		begin
			{ Refresh }
			for iy := -1 to (height + 1) do begin
				for ix := -1 to (width + 1) do begin
					tx := ox + ix;
					ty := oy + iy;
					if (tx >= 1) and (ty >= 1) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then
						BoardDrawTile(tx, ty);
				end;
			end;
		end;

	procedure EditorPasteCopyBuffer(ox, oy: integer);
		var
			ix, iy, ip, ist, tx, ty: integer;
		begin
			Dec(ox);
			Dec(oy);

			with copyBuffer do begin
				if width <= 0 then exit;

				{ Paste - Tiles }
				ip := 0;
				for iy := 1 to height do begin
					for ix := 1 to width do begin
						tx := ox + ix;
						ty := oy + iy;
						if (tx >= 1) and (ty >= 1) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then begin
							ist := GetStatIdAt(tx, ty);
							while ist > 0 do begin
								RemoveStat(ist);
								ist := GetStatIdAt(tx, ty);
							end;
							if ist < 0 then begin
								Board.Tiles[tx][ty] := tiles^[ip];
							end;
						end;
						Inc(ip);
					end;
				end;

				{ Paste - Stats }
				for ix := 1 to statCount do begin
					with stats^[ix] do begin
						tx := ox + X;
						ty := oy + Y;
					end;
					ist := GetStatIdAt(tx, ty);
					if ist < 0 then begin
						if Board.StatCount < MAX_STAT then begin
							Inc(Board.StatCount);
							EditorCopyStat(stats^[ix], Board.Stats[Board.StatCount]);
							with Board.Stats[Board.StatCount] do begin
								Inc(X, ox);
								Inc(Y, oy);
							end;
						end else begin
							Board.Tiles[tx][ty].Element := E_EMPTY;
						end;
					end;
				end;

				EditorRefreshCopyBuffer(ox + 1, oy + 1, width, height);
			end;
		end;

	procedure EditorAskAndPasteCopyBuffer(ox, oy: integer);
		procedure InvertSel;
			begin
				Dec(ox);
				Dec(oy);
				VideoInvert(ox, oy, ox + copyBuffer.width, oy + copyBuffer.height);
				Inc(ox);
				Inc(oy);
			end;
		begin
			InvertSel;
			while true do begin
				InputReadWaitKey;
				case UpCase(InputKeyPressed) of
					KEY_ENTER: begin
						InvertSel;
						EditorPasteCopyBuffer(ox, oy);
						exit;
					end;
					KEY_ESCAPE: begin
						InvertSel;
						exit;
					end;
				end;
			end;
		end;

	procedure EditorCopyCopyBuffer(ox1, oy1, ox2, oy2: integer; doCut: boolean);
		var
			ix, iy, ip, ist, tx, ty: integer;
		begin
			EditorFreeCopyBuffer;
			if ox2 < ox1 then begin
				ix := ox1;
				ox1 := ox2;
				ox2 := ix;
			end;
			if oy2 < oy1 then begin
				ix := oy1;
				oy1 := oy2;
				oy2 := ix;
			end;

			with copyBuffer do begin
				Dec(ox1);
				Dec(oy1);

				width := ox2 - ox1;
				height := oy2 - oy1;
				statCount := 0;

				{ Copy - Tiles, count stats }
				GetMem(tiles, Integer(width) * Integer(height) * SizeOf(TTile));
				ip := 0;
				for iy := 1 to height do begin
					for ix := 1 to width do begin
						tx := ox1 + ix;
						ty := oy1 + iy;

						with tiles^[ip] do begin
							Element := E_EMPTY;
							Color := $0F;
						end;

						if (tx >= 1) and (ty >= 1) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then begin
							ist := GetStatIdAt(tx, ty);
							if ist <> 0 then begin
								tiles^[ip] := Board.Tiles[tx][ty];
								if ist > 0 then Inc(statCount);
							end;
						end;

						Inc(ip);
					end;
				end;

				{ Copy - Stats }
				if statCount > 0 then begin
					GetMem(stats, statCount * SizeOf(TStat));
					ip := 0;
					for iy := 1 to height do begin
						for ix := 1 to width do begin
							tx := ox1 + ix;
							ty := oy1 + iy;
							if (tx >= 1) and (ty >= 1) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then begin
								ist := GetStatIdAt(tx, ty);
								if ist > 0 then begin
									Inc(ip);
									EditorCopyStat(Board.Stats[ist], stats^[ip]);
									with stats^[ip] do begin
										X := ix;
										Y := iy;
									end;
								end;
							end;
						end;
					end;
					{ if ip <> statCount then RunError(201); }
				end;

				if doCut then begin
					for iy := 1 to height do
						for ix := 1 to width do
							EditorPlaceTile(ox1 + ix, oy1 + iy);
				end;

				EditorRefreshCopyBuffer(ox1, oy1, width, height);
			end;
		end;

	procedure EditorUpdateCursorPos(drawCursor: boolean);
		begin
			if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
				Inc(cursorX, InputDeltaX);
				if cursorX < 1 then
					cursorX := 1;
				if cursorX > BOARD_WIDTH then
					cursorX := BOARD_WIDTH;

				Inc(cursorY, InputDeltaY);
				if cursorY < 1 then
					cursorY := 1;
				if cursorY > BOARD_HEIGHT then
					cursorY := BOARD_HEIGHT;

				if drawCursor then
					VideoWriteText(cursorX - 1, cursorY - 1, $0F, #197);

				if (InputKeyPressed = #0) and InputJoystickEnabled then
					AccurateDelay(70);
				InputShiftAccepted := false;
			end;
		end;

	procedure EditorSelectAndCopyCopyBuffer(ox1, oy1: integer; doCut: boolean);
		var
			ix, iy, oldCx, oldCy: integer;
			running: boolean;
		procedure InvertLocal;
			begin
				VideoInvert(ox1 - 1, oy1 - 1, oldCx - 1, oldCy - 1);
			end;
		begin
			running := true;

			oldCx := cursorX;
			oldCy := cursorY;

			BoardDrawTile(ox1, oy1);
			InvertLocal;

			while running do begin
				InputUpdate;

				EditorUpdateCursorPos(false);
				if (oldCx <> cursorX) or (oldCy <> cursorY) then begin
					InvertLocal;
					oldCx := cursorX;
					oldCy := cursorY;
					InvertLocal;
				end;

				case UpCase(InputKeyPressed) of
					KEY_ESCAPE: begin
						running := false;
					end;
					KEY_ENTER: begin
						EditorCopyCopyBuffer(ox1, oy1, oldCx, oldCy, doCut);
						running := false;
					end;
				end;
			end;

			if cursorX > ox1 then cursorX := ox1;
			if cursorY > oy1 then cursorY := oy1;
		end;

	procedure EditorTypeCharacter(ch: byte);
		var
			i: integer;
		begin
			if EditorPrepareModifyTile(cursorX, cursorY) then begin
				i := (cursorColor and $07) + (E_TEXT_MIN - 1);
				if i < E_TEXT_MIN then i := E_TEXT_MIN + 6;
				with Board.Tiles[cursorX][cursorY] do begin
					Element := i;
					Color := ch;
				end;
				EditorDrawTileAndNeighborsAt(cursorX, cursorY);
				InputDeltaX := 1;
				InputDeltaY := 0;
			end;
		end;


	procedure EditorFloodFill(x, y: integer; from: TTile);
		var
			i: integer;
			tileAt, tilePlaced: TTile;
			toFill, filled: byte;
			xPosition: array[0 .. 255] of integer;
			yPosition: array[0 .. 255] of integer;
		begin
			toFill := 1;
			filled := 0;
			while toFill <> filled do begin
				tileAt := Board.Tiles[x][y];
				EditorPlaceTile(x, y);
				tilePlaced := Board.Tiles[x][y];
				if (tilePlaced.Element <> tileAt.Element)
					or (tilePlaced.Color <> tileAt.Color) then
					for i := 0 to 3 do
					with Board.Tiles[x + NeighborDeltaX[i]][y + NeighborDeltaY[i]] do begin
							if (Element = from.Element)
								and ((from.Element = 0) or (Color = from.Color)) then
							begin
								xPosition[toFill] := x + NeighborDeltaX[i];
								yPosition[toFill] := y + NeighborDeltaY[i];
								Inc(toFill);
							end;
						end;

				Inc(filled);
				x := xPosition[filled];
				y := yPosition[filled];
			end;
		end;

	begin
		EditorWorldCanOpenCheck(true);
		InitElementsEditor;
		CurrentTick := 0;
		wasModified := false;
		cursorX := 30;
		cursorY := 12;
		drawMode := DrawingOff;
		cursorPattern := 1;
		cursorColor := $0E;
		colorIgnoreDefaults := false;
		cursorBlinker := 0;
		inputByte := 0;

		for i := 1 to COPIED_TILES_COUNT do
			EditorClearPattern(copiedTiles[i], true);
		FillChar(copyBuffer, SizeOf(TEditorCopyBuffer), 0);

		if World.Info.CurrentBoard <> 0 then
			BoardChange(World.Info.CurrentBoard);

		EditorDrawRefresh;
		if World.BoardCount = 0 then
			EditorAppendBoard;

		editorExitRequested := false;
		repeat
			if drawMode = DrawingOn then
				EditorPlaceTile(cursorX, cursorY);
			InputUpdate;
			if (InputKeyPressed = #0) and (InputDeltaX = 0) and (InputDeltaY = 0) and not InputShiftPressed then begin
				if SoundHasTimeElapsed(TickTimeCounter, 15) then
					cursorBlinker := (cursorBlinker + 1) mod 3;
				if cursorBlinker = 0  then
					BoardDrawTile(cursorX, cursorY)
				else
					VideoWriteText(cursorX - 1, cursorY - 1, $0F, #197);
			end else begin
				BoardDrawTile(cursorX, cursorY);
			end;

			if drawMode = TextEntry then begin
				if (InputKeyPressed >= #32) and (InputKeyPressed < #128) then begin
					EditorTypeCharacter(Ord(InputKeyPressed));
				end else if (InputKeyPressed = KEY_BACKSPACE) and (cursorX > 1)
					and EditorPrepareModifyTile(cursorX - 1, cursorY) then
				begin
					Dec(cursorX);
				end else if (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) then begin
					drawMode := DrawingOff;
					EditorUpdateDrawMode;
				end else if (InputKeyPressed = KEY_F10) then begin
					SidebarPromptCharacter(true, 63, 3, 'Character?', inputByte);
					EditorTypeCharacter(inputByte);
					EditorDrawSidebar;
				end;
				InputKeyPressed := #0;
			end;

			with Board.Tiles[cursorX][cursorY] do begin
				if InputShiftPressed or (InputKeyPressed = ' ') then begin
					InputShiftAccepted := true;

					canModify := (Element = 0) or (InputDeltaX <> 0) or (InputDeltaY <> 0);
					if not canModify and ElementDefs[Element].PlaceableOnTop and (cursorPattern > EditorPatternCount) then begin
						{ Place stats -> Under }
						canModify := copiedTiles[cursorPattern - EditorPatternCount].hasStat;
					end;

					if canModify then begin
						EditorPlaceTile(cursorX, cursorY);
					end else begin
						canModify := EditorPrepareModifyTile(cursorX, cursorY);
						if canModify then
							Board.Tiles[cursorX][cursorY].Element := 0;
					end;
				end else if (InputKeyPressed = KEY_DELETE) then begin
					EditorRemoveTile(cursorX, cursorY);
				end;

				EditorUpdateCursorPos(true);

				case UpCase(InputKeyPressed) of
					'0'..'9': begin
						if InputKeyPressed = '0' then
							i := 10
						else
							i := Ord(InputKeyPressed) - 48;
						if i <= COPIED_TILES_COUNT then begin
							cursorPattern := EditorPatternCount + i;
							EditorUpdateCursorPattern;
						end;
					end;
					'`': EditorDrawRefresh;
					'P': begin
						if InputKeyPressed = 'P' then begin
							if cursorPattern > 1 then
								Dec(cursorPattern)
							else
								cursorPattern := EditorPatternCount + COPIED_TILES_COUNT;
						end else begin
							if cursorPattern < (EditorPatternCount + COPIED_TILES_COUNT) then
								Inc(cursorPattern)
							else
								cursorPattern := 1;
						end;
						EditorUpdateCursorPattern;
					end;
					'C': begin
						if InputKeyPressed = 'C' then
							cursorColor := (cursorColor and $8F) or ((cursorColor + 16) and $70)
						else
							cursorColor := (cursorColor and $F0) or ((cursorColor + 1) and $0F);
						EditorUpdateCursorColor;
					end;
					'D': begin
						colorIgnoreDefaults := not colorIgnoreDefaults;
						EditorUpdateColorIgnoreDefaults;
					end;
					'L': begin
						EditorAskSaveChanged;
						if (InputKeyPressed <> KEY_ESCAPE) and GameWorldLoad('.ZZT') then begin
							EditorWorldCanOpenCheck(false);
							wasModified := false;
							EditorDrawRefresh;
						end;
						EditorDrawSidebar;
					end;
					'S': begin
						GameWorldSave('Save world:', LoadedGameFileName, '.ZZT');
						if InputKeyPressed <> KEY_ESCAPE then
							wasModified := false;
						EditorDrawSidebar;
					end;
					'Z': begin
						if SidebarPromptYesNo('Clear board? ', false) then begin
							for i := Board.StatCount downto 1 do
								RemoveStat(i);
							BoardCreate;
							EditorDrawRefresh;
						end else begin
							EditorDrawSidebar;
						end;
					end;
					'N': begin
						if SidebarPromptYesNo('Make new world? ', false) and (InputKeyPressed <> KEY_ESCAPE) then begin
							EditorAskSaveChanged;
							if (InputKeyPressed <> KEY_ESCAPE) then begin
								WorldUnload;
								WorldCreate;
								EditorDrawRefresh;
								wasModified := false;
							end;
						end;
						EditorDrawSidebar;
					end;
					'Q', KEY_ESCAPE: begin
						editorExitRequested := true;
					end;
					'B': begin
						i := EditorSelectBoard('Switch boards', World.Info.CurrentBoard, false, false);
						if (InputKeyPressed <> KEY_ESCAPE) then begin
							if (i > World.BoardCount) then
								if SidebarPromptYesNo('Add new board? ', false) then
									EditorAppendBoard;
							BoardChange(i);
							EditorDrawRefresh;
						end;
						EditorDrawSidebar;
					end;
					'?': begin
						GameDebugPrompt;
						EditorDrawSidebar;
					end;
					KEY_TAB: begin
						if drawMode = DrawingOff then
							drawMode := DrawingOn
						else
							drawMode := DrawingOff;
						EditorUpdateDrawMode;
					end;
					KEY_F5: begin
						VideoWriteText(cursorX - 1, cursorY - 1, $0F, #197);
						for i := 3 to 20 do
							SidebarClearLine(i);
						VideoWriteText(65, 4, $1E, 'Advanced:');
						VideoWriteText(61, 5, $70, ' E ');
						VideoWriteText(65, 5, $1F, 'Board edge');
						VideoWriteText(78, 5, cursorColor, 'E');
						InputReadWaitKey;
						case UpCase(InputKeyPressed) of
							'E': begin
								if EditorPrepareModifyTile(cursorX, cursorY) then
									EditorSetAndCopyTile(cursorX, cursorY, E_BOARD_EDGE, cursorColor);
							end;
						end;
						EditorDrawSidebar;
					end;
					KEY_F1, KEY_F2, KEY_F3: begin
						VideoWriteText(cursorX - 1, cursorY - 1, $0F, #197);
						for i := 3 to 20 do
							SidebarClearLine(i);
						case InputKeyPressed of
							KEY_F1: selectedCategory := CATEGORY_ITEM;
							KEY_F2: selectedCategory := CATEGORY_CREATURE;
							KEY_F3: selectedCategory := CATEGORY_TERRAIN;
						end;
						i := 3; { Y position for text writing }
						for iElem := 0 to MAX_ELEMENT do begin
							if ElementDefs[iElem].EditorCategory = selectedCategory then begin
								if Length(ElementDefs[iElem].CategoryName) <> 0 then begin
									Inc(i);
									VideoWriteText(65, i, $1E, ElementDefs[iElem].CategoryName);
									Inc(i);
								end;

								VideoWriteText(61, i, ((i and 1) shl 6) + $30, ' ' + ElementDefs[iElem].EditorShortcut + ' ');
								VideoWriteText(65, i, $1F, ElementDefs[iElem].Name);
								VideoWriteText(78, i, EditorGetDrawingColor(iElem), ElementDefs[iElem].Character);

								Inc(i);
							end;
						end;
						InputReadWaitKey;
						for iElem := 1 to MAX_ELEMENT do begin
							if (ElementDefs[iElem].EditorCategory = selectedCategory)
								and (ElementDefs[iElem].EditorShortcut = UpCase(InputKeyPressed)) then
							begin
								if iElem = E_PLAYER then begin
									if EditorPrepareModifyTile(cursorX, cursorY) then
										MoveStat(0, cursorX, cursorY);
								end else begin
									elemMenuColor := EditorGetDrawingColor(iElem);

									if ElementDefs[iElem].Cycle = -1 then begin
										if EditorPrepareModifyTile(cursorX, cursorY) then
											EditorSetAndCopyTile(cursorX, cursorY, iElem, elemMenuColor);
									end else begin
										if EditorPrepareModifyStatAtCursor then begin
											AddStat(cursorX, cursorY, iElem, elemMenuColor,

												ElementDefs[iElem].Cycle, StatTemplateDefault);
											with Board.Stats[Board.StatCount] do begin
												if Length(ElementDefs[iElem].Param1Name) <> 0 then
													P1 := World.EditorStatSettings[iElem].P1;
												if Length(ElementDefs[iElem].Param2Name) <> 0 then
													P2 := World.EditorStatSettings[iElem].P2;
												if Length(ElementDefs[iElem].ParamDirName) <> 0 then begin
													StepX := World.EditorStatSettings[iElem].StepX;
													StepY := World.EditorStatSettings[iElem].StepY;
												end;
												if Length(ElementDefs[iElem].ParamBoardName) <> 0 then
													P3 := World.EditorStatSettings[iElem].P3;
											end;
											EditorEditStat(Board.StatCount);
											if InputKeyPressed = KEY_ESCAPE then
												RemoveStat(Board.StatCount);
										end;
									end;
								end;
							end;
						end;
						EditorDrawSidebar;
					end;
					KEY_F4: begin
						if drawMode <> TextEntry then
							drawMode := TextEntry
						else
							drawMode := DrawingOff;
						EditorUpdateDrawMode;
					end;
					'H': begin
						TextWindowDisplayFile('editor.hlp', 'World editor help');
					end;
					'X': begin
						EditorFloodFill(cursorX, cursorY, Board.Tiles[cursorX][cursorY]);
					end;
					'!': begin
						EditorEditTextFile;
						EditorDrawSidebar;
					end;
					'T': begin
						EditorTransferBoard;
					end;
					KEY_ENTER: begin
						i := GetStatIdAt(cursorX, cursorY);
						if i >= 0 then begin
							EditorEditStat(i);
							EditorDrawSidebar;
						end else begin
							EditorCopyPatternToCurrent(cursorX, cursorY);
							EditorUpdateCopiedPatterns;
						end;
					end;
					'I': begin
						EditorEditBoardInfo;
						TransitionDrawToBoard;
					end;
					KEY_CTRL_X: begin
						EditorSelectAndCopyCopyBuffer(cursorX, cursorY, true);
					end;
					KEY_CTRL_C: begin
						EditorSelectAndCopyCopyBuffer(cursorX, cursorY, false);
					end;
					KEY_CTRL_V: begin
						EditorAskAndPasteCopyBuffer(cursorX, cursorY);
					end;
				end;
			end;

			if editorExitRequested then begin
				EditorAskSaveChanged;
				if InputKeyPressed = KEY_ESCAPE then begin
					editorExitRequested := false;
					EditorDrawSidebar;
				end;
			end;
		until editorExitRequested;

		EditorFreeCopyBuffer;
		for i := 1 to COPIED_TILES_COUNT do
			EditorClearPattern(copiedTiles[i], false);
		InputKeyPressed := #0;
		InitElementsGame;
	end;
{$ENDIF}

procedure HighScoresLoad;
	var
		f: file of THighScoreList;
		i: integer;
	begin
		Assign(f, World.Info.Name + '.HI');
		Reset(f);
		if IOResult = 0 then begin
			Read(f, HighScoreList);
		end;
		Close(f);
		if IOResult <> 0 then begin
			for i := 1 to 30 do begin
				HighScoreList[i].Name := '';
				HighScoreList[i].Score := -1;
			end;
		end;
	end;

procedure HighScoresSave;
	var
		f: file of THighScoreList;
	begin
		Assign(f, World.Info.Name + '.HI');
		Rewrite(f);
		Write(f, HighScoreList);
		Close(f);
		if DisplayIOError then begin end;
	end;

{$F+}

procedure HighScoresInitTextWindow(var state: TTextWindowState);
	var
		i: integer;
		scoreStr: string;
	begin
		TextWindowInitState(state);
		TextWindowAppend(state, 'Score  Name');
		TextWindowAppend(state, '-----  ----------------------------------');
		for i := 1 to HIGH_SCORE_COUNT do begin
			if Length(HighScoreList[i].Name) <> 0 then begin
				Str(HighScoreList[i].Score:5, scoreStr);
				TextWindowAppend(state, scoreStr + '  ' + HighScoreList[i].Name);
			end;
		end;
	end;

procedure HighScoresDisplay(linePos: integer);
	var
		state: TTextWindowState;
	begin
		state.LinePos := linePos;
		HighScoresInitTextWindow(state);
		if (state.LineCount > 2) then begin
			state.Title := 'High scores for ' + World.Info.Name;
			TextWindowDrawOpen(state);
			TextWindowSelect(state, TWS_VIEWING_FILE);
			TextWindowDrawClose(state);
		end;
		TextWindowFree(state);
	end;

{$IFDEF EDITOR}
procedure EditorOpenEditTextWindow(var state: TTextWindowState; extension: TExtensionString;
	syntaxHighlighting: boolean);
	begin
		SidebarClear;
		VideoWriteText(61, 7, $30, ' Return ');
		VideoWriteText(69, 7, $1F, ' New line');
		VideoWriteText(61, 8, $70, ' Ctrl-Y ');
		VideoWriteText(69, 8, $1F, ' Del line');
		VideoWriteText(61, 10, $30, ' '#24#25#27#26' ');
		VideoWriteText(67, 10, $1F, ' Move cursor');
		VideoWriteText(61, 12, $70, ' Ins ');
		VideoWriteText(66, 12, $1F, ' Insert: ');
		VideoWriteText(61, 13, $30, ' Del ');
		VideoWriteText(66, 13, $1F, ' Delete char');
		VideoWriteText(61, 14, $70, ' f10 ');
		VideoWriteText(66, 14, $1F, ' Custom char');
		VideoWriteText(61, 16, $30, ' Shift  ');
		VideoWriteText(69, 16, $1F, ' Select');
		VideoWriteText(61, 17, $70, ' Ctrl-X ');
		VideoWriteText(69, 17, $1F, ' Cut');
		VideoWriteText(61, 18, $30, ' Ctrl-C ');
		VideoWriteText(69, 18, $1F, ' Copy');
		VideoWriteText(61, 19, $70, ' Ctrl-V ');
		VideoWriteText(69, 19, $1F, ' Paste');
		VideoWriteText(61, 21, $30, ' Ctrl-O ');
		VideoWriteText(69, 21, $1F, ' Open file');
		VideoWriteText(61, 22, $70, ' Ctrl-S ');
		VideoWriteText(69, 22, $1F, ' Save file');
		VideoWriteText(61, 23, $30, ' Esc ');
		VideoWriteText(66, 23, $1F, ' Exit editor');
		TextWindowEdit(state, extension, syntaxHighlighting);
	end;

procedure EditorEditTextFile;
	var
		textWindow: TTextWindowState;
		filename: TFilenameString;
		extension: TExtensionString;
		i: integer;
	begin
		TextWindowInitState(textWindow);
		TextWindowPromptFilename('File to open?', filename);

		if Length(filename) <> 0 then
			TextWindowOpenFile('*' + filename, textWindow, true, true);

		extension := '.HLP';
		for i := Length(filename) downto (Length(filename) - 4) do begin
			if (i >= 1) and (filename[i] = '.') then begin
				extension := Copy(filename, i, 4);
			end;
		end;

		textWindow.Title := filename;
		TextWindowDrawOpen(textWindow);
		EditorOpenEditTextWindow(textWindow, extension, false);
		TextWindowDrawClose(textWindow);
		TextWindowFreeEdit(textWindow);
	end;
{$ENDIF}

procedure HighScoresAdd(score: integer);
	var
		textWindow: TTextWindowState;
		name: TString50;
		i, listPos: integer;
	begin
		listPos := 1;
		while (listPos <= 30) and (score < HighScoreList[listPos].Score) do
			Inc(listPos);
		if (listPos <= 30) and (score > 0) then begin
			for i := 29 downto listPos do
				HighScoreList[i + 1] := HighScoreList[i];
			HighScoreList[listPos].Score := score;
			HighScoreList[listPos].Name := '-- You! --';

			HighScoresInitTextWindow(textWindow);
			textWindow.LinePos := listPos;
			textWindow.Title := 'New high score for ' + World.Info.Name;
			TextWindowDrawOpen(textWindow);
			TextWindowDraw(textWindow, false, false);

			name := '';
			PopupPromptString('Congratulations!  Enter your name:', name, MAX_HIGH_SCORE_NAME_LENGTH);
			HighScoreList[listPos].Name := name;
			HighScoresSave;

			TextWindowDrawClose(textWindow);
			TransitionDrawToBoard;
			TextWindowFree(textWindow);
		end;
	end;

function EditorGetBoardName(boardId: integer; titleScreenIsNone: boolean): TString50;
	var
		copiedName: TString50;
	begin
		if (boardId = 0) and titleScreenIsNone then
			EditorGetBoardName := 'None'
		else if (boardId = World.Info.CurrentBoard) then
			EditorGetBoardName := Board.Name
		else begin
			ExtMemRead(World.BoardData[boardId], copiedName, SizeOf(copiedName));
			EditorGetBoardName := copiedName;
		end;
	end;

function EditorSelectBoard(title: string; currentBoard: integer; titleScreenIsNone: boolean;
	windowAlreadyOpen: boolean): integer;
	var
		i: integer;
		textWindow: TTextWindowState;
	begin
		textWindow.Title := title;
		textWindow.LinePos := currentBoard + 1;
		textWindow.Selectable := true;
		textWindow.LineCount := 0;
		for i := 0 to World.BoardCount do begin
			TextWindowAppend(textWindow, EditorGetBoardName(i, titleScreenIsNone));
		end;
		TextWindowAppend(textWindow, 'Add new board');
		if not windowAlreadyOpen then TextWindowDrawOpen(textWindow);
		TextWindowSelect(textWindow, TWS_IGNORE_HYPERLINKS);
		if not windowAlreadyOpen then TextWindowDrawClose(textWindow);
		TextWindowFree(textWindow);
		if InputKeyPressed = KEY_ESCAPE then
			EditorSelectBoard := 0
		else
			EditorSelectBoard := textWindow.LinePos - 1;
	end;

end.
