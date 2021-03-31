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
unit TxtWind;

interface
	uses ZVideo;
	const
		MAX_TEXT_WINDOW_LINES = 1024;
		MAX_RESOURCE_DATA_FILES = 24;
		TextWindowX = 5;
		TextWindowY = 3;
		TextWindowWidth = 50;
		TextWindowHeight = 18;
		MAX_LINE_LENGTH_EDIT = 58;
		MAX_LINE_LENGTH = 50;
	type
		TTextWindowLine = string[MAX_LINE_LENGTH_EDIT];
		TTextWindowState = record
			Selectable: boolean;
			LineCount: integer;
			LinePos: integer;
			Lines: array[1 .. MAX_TEXT_WINDOW_LINES] of ^TTextWindowLine;
			Hyperlink: string[20];
			Title: TTextWindowLine;
			LoadedFilename: string[50];
			ScreenCopy: array[1 .. 25] of TScreenCopyLine;
		end;
		TResourceDataHeader = record
			Version: integer;
			EntryCount: integer;
			Name: array[1 .. MAX_RESOURCE_DATA_FILES] of string[12];
			FileOffset: array[1 .. MAX_RESOURCE_DATA_FILES] of longint;
		end;
	var
		TextWindowStrInnerEmpty: TVideoLine;
		TextWindowStrText: TVideoLine;
		TextWindowStrInnerLine: TVideoLine;
		TextWindowStrTop: TVideoLine;
		TextWindowStrBottom: TVideoLine;
		TextWindowStrSep: TVideoLine;
		TextWindowStrInnerSep: TVideoLine;
		TextWindowStrInnerArrows: TVideoLine;
		TextWindowRejected: boolean;
		ResourceDataFileName: string[128];
		ResourceDataHeader: TResourceDataHeader;
		{ OrderPrintId: ^string; }
	procedure TextWindowInitState(var state: TTextWindowState);
	procedure TextWindowDrawOpen(var state: TTextWindowState);
	procedure TextWindowDrawClose(var state: TTextWindowState);
	procedure TextWindowDraw(var state: TTextWindowState; withoutFormatting, viewingFile: boolean);
	procedure TextWindowAppend(var state: TTextWindowState; line: TTextWindowLine);
	procedure TextWindowAppendEdit(var state: TTextWindowState; line: TTextWindowLine);
	procedure TextWindowFree(var state: TTextWindowState);
	procedure TextWindowFreeEdit(var state: TTextWindowState);
	procedure TextWindowSelect(var state: TTextWindowState; hyperlinkAsSelect, viewingFile: boolean);
	procedure TextWindowEdit(var state: TTextWindowState; syntaxHighlighting: boolean);
	procedure TextWindowOpenFile(filename: TTextWindowLine; var state: TTextWindowState; editing: boolean);
	procedure TextWindowSaveFile(filename: TTextWindowLine; var state: TTextWindowState);
	procedure TextWindowDisplayFile(filename, title: string);
	procedure TextWindowInit;

implementation
{$IFDEF PRINTTXT}
uses Sounds, Input, Keys, Printer, Game;
{$ELSE}
uses Sounds, Input, Keys, Game;
{$ENDIF}
type
	TTextWindowLineBuffer = array[1 .. MAX_TEXT_WINDOW_LINES] of ^TTextWindowLine;

function UpCaseString(input: string): string;
	var
		i: integer;
	begin
		for i := 1 to Length(input) do
			input[i] := UpCase(input[i]);
		UpCaseString := input;
	end;

procedure TextWindowInitState(var state: TTextWindowState);
	begin
		with state do begin
			LineCount := 0;
			LinePos := 1;
			LoadedFilename := '';
		end;
	end;

procedure TextWindowDrawTitle(color: integer; title: TTextWindowLine);
	begin
		VideoWriteText(TextWindowX + 2, TextWindowY + 1, color, TextWindowStrInnerEmpty);
		VideoWriteText(TextWindowX + ((TextWindowWidth - Length(title)) div 2), TextWindowY + 1, color, title);
	end;

procedure TextWindowDrawOpen(var state: TTextWindowState);
	var
		ix, iy: integer;
	begin
		with state do begin
			for iy := 1 to (TextWindowHeight + 1) do
				VideoMove(TextWindowX, iy + TextWindowY - 1, TextWindowWidth, @ScreenCopy[iy], false);

			for iy := (TextWindowHeight shr 1) downto 0 do begin
				VideoWriteText(TextWindowX, TextWindowY + iy + 1, $0F, TextWindowStrText);
				VideoWriteText(TextWindowX, TextWindowY + TextWindowHeight - iy - 1, $0F, TextWindowStrText);
				VideoWriteText(TextWindowX, TextWindowY + iy, $0F, TextWindowStrTop);
				VideoWriteText(TextWindowX, TextWindowY + TextWindowHeight - iy, $0F, TextWindowStrBottom);
				AccurateDelay(25);
			end;

			VideoWriteText(TextWindowX, TextWindowY + 2, $0F, TextWindowStrSep);
			TextWindowDrawTitle($1E, Title);
		end;
	end;

procedure TextWindowDrawClose(var state: TTextWindowState);
	var
		ix, iy: integer;
		unk1, unk2: integer;
	begin
		with state do begin
			for iy := 0 to (TextWindowHeight shr 1) do begin
				VideoWriteText(TextWindowX, TextWindowY + iy, $0F, TextWindowStrTop);
				VideoWriteText(TextWindowX, TextWindowY + TextWindowHeight - iy, $0F, TextWindowStrBottom);
				AccurateDelay(18);
				VideoMove(TextWindowX, TextWindowY + iy, TextWindowWidth,
					@ScreenCopy[iy + 1], true);
				VideoMove(TextWindowX, TextWindowY + TextWindowHeight - iy, TextWindowWidth,
					@ScreenCopy[(TextWindowHeight - iy) + 1], true);
			end;
		end;
	end;

procedure TextWindowDrawLine(var state: TTextWindowState; lpos: integer; withoutFormatting, viewingFile: boolean);
	var
		lineY: integer;
		textOffset, textColor, textX: integer;
	begin
		with state do begin
			lineY := ((TextWindowY + lpos) - LinePos) + (TextWindowHeight shr 1) + 1;
			if lpos = LinePos then
				VideoWriteText(TextWindowX + 2, lineY, $1C, TextWindowStrInnerArrows)
			else
				VideoWriteText(TextWindowX + 2, lineY, $1E, TextWindowStrInnerEmpty);
			if (lpos > 0) and (lpos <= LineCount) then begin
				if withoutFormatting then begin
					VideoWriteText(TextWindowX + 4, lineY, $1E, Lines[lpos]^);
				end else begin
					textOffset := 1;
					textColor := $1E;
					textX := TextWindowX + 4;
					if Length(state.Lines[lpos]^) > 0 then begin
						case state.Lines[lpos]^[1] of
							'!': begin
								textOffset := Pos(';', Lines[lpos]^) + 1;
								VideoWriteText(textX + 2, lineY, $1D, #16);
								Inc(textX, 5);
								textColor := $1F;
							end;
							':': begin
								textOffset := Pos(';', Lines[lpos]^) + 1;
								textColor := $1F;
							end;
							'$': begin
								textOffset := 2;
								textColor := $1F;
								textX := (textX - 4) + ((TextWindowWidth - Length(Lines[lpos]^)) div 2);
							end;
						end;
					end;
					if textOffset > 0 then begin
						VideoWriteText(textX, lineY, textColor,
							Copy(Lines[lpos]^, textOffset,Length(Lines[lpos]^) - textOffset + 1));
					end;
				end;
			end else if (lpos = 0) or (lpos = (state.LineCount + 1)) then begin
				VideoWriteText(TextWindowX + 2, lineY, $1E, TextWindowStrInnerSep);
{$IFDEF PRINTTXT}
			end else if (lpos = -4) and viewingFile then begin
				VideoWriteText(TextWindowX + 2, lineY, $1A, '   Use            to view text,');
				VideoWriteText(TextWindowX + 2 + 7, lineY, $1F, #24' '#25', Enter');
			end else if (lpos = -3) and viewingFile then begin
				VideoWriteText(TextWindowX + 2 + 1, lineY, $1A, '                 to print.');
				VideoWriteText(TextWindowX + 2 + 12, lineY, $1F, 'Alt-P');
{$ELSE}
			end else if (lpos = -3) and viewingFile then begin
				VideoWriteText(TextWindowX + 2, lineY, $1A, '   Use            to view text.');
				VideoWriteText(TextWindowX + 2 + 7, lineY, $1F, #24' '#25', Enter');
{$ENDIF}
			end;
		end;
	end;

procedure TextWindowDraw(var state: TTextWindowState; withoutFormatting, viewingFile: boolean);
	var
		i: integer;
		unk1: integer;
	begin
		for i := 0 to (TextWindowHeight - 4) do
			TextWindowDrawLine(state, state.LinePos - (TextWindowHeight shr 1) + i + 2,
				withoutFormatting, viewingFile);
		TextWindowDrawTitle($1E, state.Title);
	end;

procedure TextWindowAppend(var state: TTextWindowState; line: TTextWindowLine);
	var
		len: integer;
	begin
		with state do begin
			len := Length(line);
			if len > MAX_LINE_LENGTH then len := MAX_LINE_LENGTH;

			LineCount := LineCount + 1;
			GetMem(Lines[LineCount], len + 1);
			Lines[LineCount]^ := Copy(line, 1, len);
		end;
	end;

procedure TextWindowAppendEdit(var state: TTextWindowState; line: TTextWindowLine);
	begin
		with state do begin
			if LineCount >= MAX_TEXT_WINDOW_LINES then exit;
			Inc(LineCount);
			New(Lines[LineCount]);
			Lines[LineCount]^ := Copy(line, 1, MAX_LINE_LENGTH_EDIT);
		end;
	end;

procedure TextWindowFree(var state: TTextWindowState);
	begin
		with state do begin
			while LineCount > 0 do begin
				FreeMem(Lines[LineCount], Ord(Lines[LineCount]^[0]));
				LineCount := LineCount - 1;
			end;
			LoadedFilename := '';
		end;
	end;

procedure TextWindowFreeEdit(var state: TTextWindowState);
	begin
		with state do begin
			while LineCount > 0 do begin
				Dispose(Lines[LineCount]);
				Dec(LineCount);
			end;
			LoadedFilename := '';
		end;
	end;

{$IFDEF PRINTTXT}
procedure TextWindowPrint(var state: TTextWindowState);
	var
		iLine, iChar: integer;
		line: string;
	begin
		with state do begin
			Rewrite(Lst);
			for iLine := 1 to LineCount do begin
				line := Lines[iLine]^;
				if Length(line) > 0 then begin
					case line[1] of
						'$': begin
							Delete(line, 1, 1);
							for iChar := ((80 - Length(line)) div 2) downto 1 do
								line := ' ' + line;
						end;
						'!', ':': begin
							iChar := Pos(';', line);
							if iChar > 0 then
								Delete(line, 1, iChar)
							else
								line := '';
						end;
					else
						line := '          ' + line
					end;
				end;
				WriteLn(Lst, line);
				if IOResult <> 0 then begin
					Close(Lst);
					exit;
				end;
			end;
			Write(Lst, Chr(12) { form feed });
			Close(Lst);
		end;
	end;
{$ENDIF}

procedure TextWindowSelect(var state: TTextWindowState; hyperlinkAsSelect, viewingFile: boolean);
	var
		newLinePos: integer;
		unk1: integer;
		iLine, iChar: integer;
		pointerStr: string[20];
	label LabelMatched;
	label LabelNotMatched;
	begin
		with state do begin
			TextWindowRejected := false;
			Hyperlink := '';
			TextWindowDraw(state, false, viewingFile);
			repeat
				InputUpdate;
				newLinePos := LinePos;
				if InputDeltaY <> 0 then begin
					Inc(newLinePos, InputDeltaY);
				end else if InputShiftPressed or (InputKeyPressed = KEY_ENTER) then begin
					InputShiftAccepted := true;
					if (Lines[LinePos]^[1]) = '!' then begin
						pointerStr := Copy(Lines[LinePos]^, 2, Length(Lines[LinePos]^) - 1);

						if Pos(';', pointerStr) > 0 then begin
							pointerStr := Copy(pointerStr, 1, Pos(';', pointerStr) - 1);
						end;

						if pointerStr[1] = '-' then begin
							Delete(pointerStr, 1, 1);
							TextWindowFree(state);
							TextWindowOpenFile(pointerStr, state, false);
							if state.LineCount = 0 then
								exit
							else begin
								viewingFile := true;
								newLinePos := LinePos;
								TextWindowDraw(state, false, viewingFile);
								InputKeyPressed := #0;
								InputShiftPressed := false;
							end;
						end else begin
							if hyperlinkAsSelect then begin
								Hyperlink := pointerStr;
							end else begin
								pointerStr := ':' + pointerStr;
								for iLine := 1 to LineCount do begin
									if Length(pointerStr) > Length(Lines[iLine]^) then begin
									end else begin
										for iChar := 1 to Length(pointerStr) do begin
											if UpCase(pointerStr[iChar]) <> UpCase(Lines[iLine]^[iChar]) then
												goto LabelNotMatched;
										end;
										newLinePos := iLine;
										InputKeyPressed := #0;
										InputShiftPressed := false;
										goto LabelMatched;
									LabelNotMatched:
									end;
								end;
							end;
						end;
					end;
				end else begin
					if InputKeyPressed = KEY_PAGE_UP then begin
						newLinePos := LinePos - TextWindowHeight + 4;
					end else if InputKeyPressed = KEY_PAGE_DOWN then begin
						newLinePos := LinePos + TextWindowHeight - 4;
{$IFDEF PRINTTXT}
					end else if InputKeyPressed = KEY_ALT_P then begin
						TextWindowPrint(state);
{$ENDIF}
					end;
				end;

			LabelMatched:
				if newLinePos < 1 then
					newLinePos := 1
				else if newLinePos > state.LineCount then
					newLinePos := LineCount;

				if newLinePos <> LinePos then begin
					LinePos := newLinePos;
					TextWindowDraw(state, false, viewingFile);
					if (Lines[LinePos]^[1]) = '!' then
						if hyperlinkAsSelect then
							TextWindowDrawTitle($1E, #174'Press ENTER to select this'#175)
						else
							TextWindowDrawTitle($1E, #174'Press ENTER for more info'#175);
				end;
				if InputJoystickMoved then begin
					AccurateDelay(35);
				end;
			until (InputKeyPressed = KEY_ESCAPE) or (InputKeyPressed = KEY_ENTER) or InputShiftPressed;
			if InputKeyPressed = KEY_ESCAPE then begin
				InputKeyPressed := #0;
				TextWindowRejected := true;
			end;
		end;
	end;

procedure TextWindowEdit(var state: TTextWindowState; syntaxHighlighting: boolean);
	var
		newLinePos: integer;
		insertMode: boolean;
		xOffset: integer;
		charPos: integer;
		i: integer;
		inputByte: byte;
		highlightLineStart, highlightLineEnd: integer;
		copyBuffer: ^TTextWindowLineBuffer;
		copyBufferLines: integer;
		forceFullRedraw: boolean;
		shiftHeld: boolean;
	procedure DrawLineEdit(lpos: integer);
		var
			i, lineX, lineY: integer;
			textColor: byte;
		begin
			with state do begin
				lineY := ((TextWindowY + lpos) - LinePos) + (TextWindowHeight div 2) + 1;
				if lpos = LinePos then begin
					VideoWriteText(TextWindowX + 2, lineY, $1C, #175);
					VideoWriteText(TextWindowX + (TextWindowWidth - 4), lineY, $1C, #174);
				end else begin
					VideoWriteText(TextWindowX + 2, lineY, $1C, ' ');
					VideoWriteText(TextWindowX + (TextWindowWidth - 4), lineY, $1C, ' ');
				end;
				VideoWriteText(TextWindowX + 3, lineY, $1E, ' ');
				if (lpos > 0) and (lpos <= LineCount) then begin
					textColor := $1E;
					if (lpos >= highlightLineStart) and (lpos <= highlightLineEnd) then begin
						textColor := $70;
					end else if syntaxHighlighting and (not VideoMonochrome) then begin
						case Lines[lpos]^[1] of
							#39: textColor := $1B; { comments }
							':': textColor := $1C; { labels }
							'$', '!': textColor := $1F; { centered text, selection }
							'@': textColor := $1D; { program name }
							'/', '?', '#': textColor := $1A; { direction/command }
						end;
					end;
					lineX := xOffset + 1;
					for i := 1 to (TextWindowWidth - 8) do begin
						if lineX > Length(Lines[lpos]^) then
							VideoWriteText(TextWindowX + 3 + i, lineY, $1E, ' ')
						else
							VideoWriteText(TextWindowX + 3 + i, lineY, textColor, Lines[lpos]^[lineX]);
						Inc(lineX);
					end;
				end else if (lpos = 0) or (lpos = (state.LineCount + 1)) then begin
					VideoWriteText(TextWindowX + 2, lineY, $1E, TextWindowStrInnerSep);
				end else begin
					VideoWriteText(TextWindowX + 2, lineY, $1E, TextWindowStrInnerEmpty);
				end;
			end;
		end;
	procedure ClampCharPos;
		var
			i: integer;
		begin
			with state do begin
				i := Length(Lines[LinePos]^) + 1;
				if charPos > i then charPos := i;
			end;
		end;
	procedure Redraw(line: integer);
		var
			i: integer;
			promptChar: char;
			newXOffset: integer;
			fullRedraw: boolean;
		begin
			fullRedraw := (line < 0);
			newXOffset := charPos - (TextWindowWidth - 8);
			if newXOffset < 0 then newXOffset := 0;
			if newXOffset <> xOffset then begin
				xOffset := newXOffset;
				fullRedraw := true;
			end;
			if fullRedraw then begin
				for i := 0 to (TextWindowHeight - 4) do
					DrawLineEdit(state.LinePos - (TextWindowHeight div 2) + i + 2);
			end else begin
				DrawLineEdit(line);
			end;
			{ draw prompt }
			with state do begin
				if charPos > Length(Lines[LinePos]^) then
					promptChar := ' '
				else
					promptChar := state.Lines[state.LinePos]^[charPos];
				VideoWriteText(charPos - xOffset + TextWindowX + 3,
					TextWindowY + (TextWindowHeight div 2) + 1,
					$70, promptChar);
			end;
		end;
	procedure DeleteLine(lpos: integer);
		var
			i: integer;
		begin
			with state do begin
				if (lpos < 1) or (lPos > LineCount) then exit;
				if LineCount > 1 then begin
					Dispose(Lines[lpos]);
					for i := (lpos + 1) to LineCount do
						Lines[i - 1] := Lines[i];

					Dec(LineCount);
					if newLinePos > lpos then Dec(newLinePos);
				end else begin
					Lines[1]^ := '';
				end;
			end;
		end;
	procedure InsertCharacter(ch: char);
		begin
			with state do begin
				if not insertMode then begin
					Lines[LinePos]^ := Copy(Lines[LinePos]^, 1, charPos - 1)
						+ ch
						+ Copy(Lines[LinePos]^, charPos + 1, Length(Lines[LinePos]^) - charPos);
					Inc(charPos);
				end else begin
					if Length(Lines[LinePos]^) < MAX_LINE_LENGTH_EDIT then begin
						Lines[LinePos]^ := Copy(Lines[LinePos]^, 1, charPos - 1)
							+ ch
							+ Copy(Lines[LinePos]^, charPos, Length(Lines[LinePos]^) - charPos + 1);
						Inc(charPos);
					end;
				end;
			end;
		end;
	procedure ClearHighlight;
		begin
			highlightLineStart := -1;
			highlightLineEnd := -1;
		end;
	procedure AddLinePosToHighlight(lpos: integer);
		begin
			if lPos = (highlightLineStart - 1) then  begin
				highlightLineStart := lpos;
				Redraw(lpos);
			end else if lPos = (highlightLineEnd + 1) then begin
				highlightLineEnd := lpos;
				Redraw(lpos);
			end else if (lPos < highlightLineStart) or (lPos > highlightLineEnd) then begin
				if highlightLineStart = -1 then begin
					highlightLineStart := lpos;
					highlightLineEnd := lpos;
				end else begin
					ClearHighlight;
				end;
				Redraw(-1);
			end;
		end;
	procedure FreeCopyBuffer;
		begin
			if copyBufferLines > 0 then begin
				FreeMem(copyBuffer, copyBufferLines * SizeOf(pointer));
				copyBufferLines := 0;
			end;
		end;
	procedure CopyHighlightToBuffer;
		var
			i: integer;
		begin
			FreeCopyBuffer;
			if (highlightLineEnd >= highlightLineStart) and (highlightLineStart > 0) then begin
				copyBufferLines := highlightLineEnd - highlightLineStart + 1;
				GetMem(copyBuffer, copyBufferLines * SizeOf(pointer));
				for i := 1 to copyBufferLines do begin
					New(copyBuffer^[i]);
					copyBuffer^[i]^ := state.Lines[i + highlightLineStart - 1]^;
				end;
			end;
		end;
	procedure InsertLine(lpos: integer; contents: TTextWindowLine);
		var
			i: integer;
		begin
			with state do if (lpos >= 1) and (lpos <= LineCount) and (LineCount < (MAX_TEXT_WINDOW_LINES - 1)) then begin
				for i := LineCount downto lpos do
					Lines[i + 1] := Lines[i];
				New(Lines[lpos]);
				Lines[lpos]^ := contents;
				Inc(LineCount);
				if newLinePos >= lpos then Inc(newLinePos);
			end;
		end;
	begin
		with state do begin
			if LineCount = 0 then
				TextWindowAppendEdit(state, '');
			insertMode := true;
			ClearHighlight;
			copyBufferLines := 0;
			LinePos := 1;
			charPos := 1;
			Redraw(-1);
			forceFullRedraw := false;
			TextWindowDrawTitle($1E, state.Title);
			repeat
				if insertMode then
					VideoWriteText(75, 12, $1E, 'on ')
				else
					VideoWriteText(75, 12, $1E, 'off');

				ClampCharPos;
				shiftHeld := false;
				repeat
					InputUpdate;
					shiftHeld := shiftHeld or KeysShiftHeld;
				until InputKeyPressed <> #0;
				newLinePos := LinePos;

				case InputKeyPressed of
					KEY_ESCAPE: begin
						if highlightLineStart <> -1 then begin
							ClearHighlight;
							InputKeyPressed := #0;
							forceFullRedraw := true;
						end;
					end;
					KEY_F10: begin
						SidebarPromptCharacter(true, 63, 3, 'Character?', inputByte);
						InsertCharacter(Chr(inputByte));
						SidebarClearLine(3);
						SidebarClearLine(4);
						SidebarClearLine(5);
					end;
					KEY_UP: begin
						newLinePos := LinePos - 1;
						if shiftHeld and (newLinePos >= 1) then AddLinePosToHighlight(newLinePos);
					end;
					KEY_DOWN: begin
						newLinePos := LinePos + 1;
						if shiftHeld then AddLinePosToHighlight(LinePos);
					end;
					KEY_PAGE_UP: newLinePos := LinePos - TextWindowHeight + 4;
					KEY_PAGE_DOWN: newLinePos := LinePos + TextWindowHeight - 4;
					KEY_RIGHT: begin
						Inc(charPos);
						if charPos > (Length(Lines[LinePos]^) + 1) then begin
							charPos := 1;
							newLinePos := LinePos + 1;
						end;
					end;
					KEY_LEFT: begin
						Dec(charPos);
						if charPos < 1 then begin
							charPos := 255;
							newLinePos := LinePos - 1;
						end;
					end;
					KEY_ENTER: begin
						if LineCount < (MAX_TEXT_WINDOW_LINES - 1) then begin
							for i := LineCount downto (LinePos + 1) do
								Lines[i + 1] := Lines[i];

							New(Lines[LinePos + 1]);
							Lines[LinePos + 1]^
								:= Copy(Lines[LinePos]^, charPos, Length(Lines[LinePos]^) - charPos + 1);
							Lines[LinePos]^
								:= Copy(Lines[LinePos]^, 1, charPos - 1);

							newLinePos := LinePos + 1;
							charPos := 1;
							Inc(LineCount);
						end;
					end;
					KEY_BACKSPACE: begin
						if charPos > 1 then begin
							Lines[LinePos]^ :=
								Copy(Lines[LinePos]^, 1, charPos - 2)
								+ Copy(Lines[LinePos]^, charPos, Length(Lines[LinePos]^) - charPos + 1);
							Dec(charPos);
						end else if Length(Lines[LinePos]^) = 0 then begin
							DeleteLine(LinePos);
							newLinePos := LinePos - 1;
							charPos := 255;
							forceFullRedraw := true;
						end;
					end;
					KEY_INSERT: begin
						insertMode := not insertMode;
					end;
					KEY_DELETE: begin
						Lines[LinePos]^ :=
							Copy(Lines[LinePos]^, 1, charPos - 1)
							+ Copy(Lines[LinePos]^, charPos + 1, Length(Lines[LinePos]^) - charPos);
					end;
					KEY_CTRL_X: if highlightLineStart > 0 then begin
						CopyHighlightToBuffer;
						for i := highlightLineStart to highlightLineEnd do
							DeleteLine(highlightLineStart);
						ClearHighlight;
						forceFullRedraw := true;
					end;
					KEY_CTRL_C: if highlightLineStart > 0 then begin
						CopyHighlightToBuffer;
						ClearHighlight;
						forceFullRedraw := true;
					end;
					KEY_CTRL_V: if copyBufferLines > 0 then begin
						for i := copyBufferLines downto 1 do
							InsertLine(LinePos, copyBuffer^[i]^);
					end;
					KEY_CTRL_Y: begin
						if highlightLineStart > 0 then begin
							for i := highlightLineStart to highlightLineEnd do
								DeleteLine(highlightLineStart);
							ClearHighlight;
						end else begin
							DeleteLine(LinePos);
						end;
						forceFullRedraw := true;
					end;
				else
					if (InputKeyPressed >= #32) and (InputKeyPressed < #127) then
						InsertCharacter(InputKeyPressed);
				end;

				if newLinePos < 1 then begin
					newLinePos := 1;
					charPos := 1;
				end else if newLinePos > LineCount then begin
					newLinePos := LineCount;
					charPos := 255;
				end;

				if (newLinePos <> LinePos) or forceFullRedraw then begin
					LinePos := newLinePos;
					ClampCharPos;
					Redraw(-1);
					forceFullRedraw := false;
				end else begin
					ClampCharPos;
					Redraw(LinePos);
				end;

			until InputKeyPressed = KEY_ESCAPE;

			if Length(Lines[LineCount]^) = 0 then begin
				Dispose(Lines[LineCount]);
				Dec(LineCount);
			end;
		end;
		FreeCopyBuffer;
	end;

procedure TextWindowOpenFile(filename: TTextWindowLine; var state: TTextWindowState; editing: boolean);
	var
		f: file;
		tf: text;
		i: integer;
		entryPos: integer;
		retVal: boolean;
		line: ^string;
		lineLen: byte;
	label EntryPosFoundResData;
	begin
		with state do begin
			retVal := true;
			for i := 1 to Length(filename) do
				retVal := retVal and (filename[i] <> '.');
			if retVal then
				filename := filename + '.HLP';

			if filename[1] = '*' then begin
				filename := Copy(filename, 2, Length(filename) - 1);
				entryPos := -1;
			end else begin
				entryPos := 0;
			end;

			TextWindowInitState(state);
			LoadedFilename := UpCaseString(filename);
			if ResourceDataHeader.EntryCount = 0 then begin
				Assign(f, ResourceDataFileName);
				Reset(f, 1);
				if IOResult = 0 then
					BlockRead(f, ResourceDataHeader, SizeOf(ResourceDataHeader));
				if (IOResult <> 0) or (ResourceDataHeader.Version <> -2) then
					ResourceDataHeader.EntryCount := -1;
				Close(f);
			end;

			if entryPos = 0 then begin
				for i := 1 to ResourceDataHeader.EntryCount do begin
					{ assumption: LoadedFilename is UpCaseString(filename) }
					if UpCaseString(ResourceDataHeader.Name[i]) = LoadedFilename then begin
						entryPos := i;
						goto EntryPosFoundResData;
					end;
				end;
			end;
			EntryPosFoundResData:

			if entryPos <= 0 then begin
				Assign(tf, filename);
				Reset(tf);
				while (IOResult = 0) and (not Eof(tf)) do begin
					Inc(LineCount);
					New(Lines[LineCount]);
					ReadLn(tf, Lines[LineCount]^);
				end;
				Close(tf);
			end else begin
				Assign(f, ResourceDataFilename);
				Reset(f, 1);
				Seek(f, ResourceDataHeader.FileOffset[entryPos]);
				if IOResult = 0 then begin
					retVal := true;
					while (IOResult = 0) and retVal do begin
						Inc(LineCount);

						BlockRead(f, lineLen, 1);
						if editing then
							New(Lines[LineCount])
						else
							GetMem(Lines[LineCount], lineLen + 1);
						Lines[LineCount]^[0] := Chr(lineLen);
						line := Ptr(Seg(Lines[LineCount]^), Ofs(Lines[LineCount]^) + 1);

						if lineLen = 0 then begin
							Lines[LineCount]^ := '';
						end else begin
							BlockRead(f, line^, lineLen);
							if Lines[LineCount]^ = '@' then begin
								retVal := false;
								Lines[LineCount]^ := '';
							end;
						end;
					end;
				end;
				Close(f);
			end;
		end;
	end;

procedure TextWindowSaveFile(filename: TTextWindowLine; var state: TTextWindowState);
	var
		f: text;
		i: integer;
	label OnError;
	begin
		Assign(f, filename);
		Rewrite(f);
		if IOResult <> 0 then goto OnError;

		with state do begin
			for i := 1 to LineCount do begin
				WriteLn(f, Lines[i]^);
				if IOResult <> 0 then goto OnError;
			end;
		end;

	OnError:
		Close(f);
	end;

procedure TextWindowDisplayFile(filename, title: string);
	var
		state: TTextWindowState;
	begin
		state.Title := title;
		TextWindowOpenFile(filename, state, false);
		state.Selectable := false;
		if state.LineCount > 0 then begin
			TextWindowDrawOpen(state);
			TextWindowSelect(state, false, true);
			TextWindowDrawClose(state);
		end;
		TextWindowFree(state);
	end;

procedure TextWindowInit;
	var
		i: integer;
	begin
		TextWindowStrInnerEmpty[0] := Chr(TextWindowWidth - 5);
		TextWindowStrInnerLine[0] := Chr(TextWindowWidth - 5);
		for i := 1 to (TextWindowWidth - 5) do begin
			TextWindowStrInnerEmpty[i] := ' ';
			TextWindowStrInnerLine[i] := #205;
		end;
		TextWindowStrTop    := #198#209 + TextWindowStrInnerLine  + #209#181;
		TextWindowStrBottom := #198#207 + TextWindowStrInnerLine  + #207#181;
		TextWindowStrSep    :=  ' '#198 + TextWindowStrInnerLine  + #181' ';
		TextWindowStrText   :=  ' '#179 + TextWindowStrInnerEmpty + #179' ';
		TextWindowStrInnerArrows := TextWindowStrInnerEmpty;
		TextWindowStrInnerArrows[1] := #175;
		TextWindowStrInnerArrows[Length(TextWindowStrInnerArrows)] := #174;
		TextWindowStrInnerSep := TextWindowStrInnerEmpty;
		for i := 1 to (TextWindowWidth div 5) do
			TextWindowStrInnerSep[i * 5 + ((TextWindowWidth mod 5) shr 1)] := #7;
	end;

begin
	ResourceDataFileName := '';
	ResourceDataHeader.EntryCount := 0;
end.
