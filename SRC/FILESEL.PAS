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
unit FileSel;

interface
	uses GameVars;
	function FileSelect(title, extension: TString50): string;

implementation
uses Dos, TxtWind;
const
	PATH_PREVIEW_LENGTH = 24;

function FileSelect(title, extension: TString50): string;
	var
		textWindow: TTextWindowState;
		fileSearchRec: SearchRec;
		entryName: string;
		useWorldFileDesc: boolean;
		searching: boolean;
		i: integer;
		curPath: string;
		startPath: string;
		previewPath: string[PATH_PREVIEW_LENGTH + 4];
	begin
		searching := true;
		useWorldFileDesc := extension = '.ZZT';
{$IFDEF SUBDIRS}
		GetDir(0, startPath);
{$ENDIF}

		while searching do begin
			TextWindowInitState(textWindow);

{$IFDEF SUBDIRS}
			GetDir(0, curPath);
			if Length(curPath) > PATH_PREVIEW_LENGTH then
				previewPath := '...' + Copy(curPath, Length(curPath) - PATH_PREVIEW_LENGTH + 1, PATH_PREVIEW_LENGTH)
			else
				previewPath := curPath;
			textWindow.Title := title + ': ' + previewPath;
{$ELSE}
			textWindow.Title := title;
{$ENDIF}
			textWindow.Selectable := true;
			textWIndow.Hyperlink := '';

{$IFDEF SUBDIRS}
			{ Directories }
			FindFirst('*', Directory, fileSearchRec);
			while DosError = 0 do begin
				if (fileSearchRec.Attr and Directory) <> 0 then begin
					entryName := fileSearchRec.Name;
					if (Length(entryName) > 0) and (entryName <> '.') then
						if (Length(curPath) > 3) or (entryName <> '..') then
							TextWindowAppend(textWindow, '!' + entryName + ';[' + entryName + ']');
				end;
				FindNext(fileSearchRec);
			end;
{$ENDIF}
		
			{ Files }
			FindFirst('*' + extension, AnyFile, fileSearchRec);
			while DosError = 0 do begin
				if (fileSearchRec.Attr and Directory) = 0 then begin
					entryName := Copy(fileSearchRec.Name, 1, Length(fileSearchRec.name) - 4);

					if useWorldFileDesc then
						for i := 1 to WorldFileDescCount do
							if entryName = WorldFileDescKeys[i] then
								entryName := WorldFileDescValues[i];

					TextWindowAppend(textWindow, entryName);
				end;
				FindNext(fileSearchRec);
			end;

			TextWindowAppend(textWindow, 'Exit');

			TextWindowDrawOpen(textWindow);
			TextWindowSelect(textWindow, true, false);
			TextWindowDrawClose(textWindow);

			if (textWindow.LinePos = textWindow.LineCount) or TextWindowRejected then begin
				{ Exit }
				FileSelect := '';
				searching := false;
{$IFDEF SUBDIRS}
				ChDir(startPath);
			end else if Length(textWindow.Hyperlink) > 0 then begin
				{ Directory }
				ChDir(textWindow.Hyperlink);
{$ENDIF}
			end else begin
				{ File }
				entryName := textWindow.Lines[textWindow.LinePos]^;
				if Pos(' ', entryName) <> 0 then
					entryName := Copy(entryName, 1, Pos(' ', entryName) - 1);
				FileSelect := entryName;
				searching := false;
			end;

			TextWindowFree(textWindow);

			{ Clear IOResult }
			if IOResult <> 0 then begin end;
		end;
	end;

end.
